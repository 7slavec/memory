import { validateLinkGroups, type LinkGroup } from "./link-groups.ts"

type VoiceRequest = {
  transcript: string
  referenceDate: string
  timeZone: string
  locale?: string
  examples?: VoiceLearningExample[]
}

type VoiceLearningExample = {
  transcript: string
  title: string
  details?: string | null
  dueDate?: string | null
  referenceDate: string
  timeZone: string
}

type DeepSeekMessage = {
  role: "system" | "user"
  content: string
}

type DeepSeekResponse = {
  choices?: Array<{
    message?: {
      content?: string | null
    }
  }>
}

type VoiceResult = {
  sourceText: string
  kind: "reminder" | "event"
  title: string
  details: string | null
  dueDate: string | null
  endDate: string | null
  reminderOffsets: number[]
  confidence: "low" | "medium" | "high"
  ambiguities: VoiceAmbiguity[]
}

type VoiceAmbiguity =
  | "missingDate"
  | "ambiguousDate"
  | "ambiguousTime"
  | "unclearReference"
  | "multipleActions"
  | "emptyTitle"

const deepSeekURL = "https://api.deepseek.com/chat/completions"
const supportedReminderOffsets = new Set([0, 5, 15, 30, 60, 1_440, 2_880, 10_080])

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405)
  }

  // JWT verification stays enabled at the Supabase gateway. Requiring an
  // authenticated user claim also rejects the public anonymous project token,
  // so it cannot be used to spend the paid model quota outside Norka.
  const accessToken = bearerToken(request.headers.get("authorization"))
  if (!accessToken || !isAuthenticatedUserToken(accessToken)) {
    return json({ error: "authentication_required" }, 401)
  }

  const apiKey = Deno.env.get("DEEPSEEK_API_KEY")
  if (!apiKey) {
    return json({ error: "deepseek_not_configured" }, 503)
  }

  let input: VoiceRequest
  try {
    input = await request.json()
  } catch {
    return json({ error: "invalid_json" }, 400)
  }

  const transcript = input.transcript?.trim()
  if (!transcript || transcript.length > 3_000) {
    return json({ error: "invalid_transcript" }, 400)
  }

  const referenceDate = new Date(input.referenceDate)
  if (Number.isNaN(referenceDate.getTime()) || !isValidTimeZone(input.timeZone)) {
    return json({ error: "invalid_context" }, 400)
  }

  const model = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-flash"
  const personalExamples = sanitizeExamples(input.examples)
  const messages: DeepSeekMessage[] = [
    {
      role: "system",
      content: systemPrompt,
    },
    {
      role: "user",
      content: JSON.stringify({
        transcript,
        referenceDate: referenceDate.toISOString(),
        timeZone: input.timeZone,
        locale: input.locale ?? "ru_RU",
        personalSchedule: {
          morning: "08:00",
          workStarts: "09:00",
          lunch: "13:00–14:00",
          workEnds: "18:00",
          evening: "19:00",
          night: "00:00–03:00",
          explicitEarlyMorning: "04:00–05:00",
        },
        personalExamples,
      }),
    },
  ]

  let upstream: Response
  try {
    upstream = await fetch(deepSeekURL, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages,
        response_format: { type: "json_object" },
        // This endpoint is a constrained JSON parser rather than an open-ended
        // reasoning task. Non-thinking mode removes an unnecessary generation
        // phase and noticeably shortens the wait after recording.
        thinking: { type: "disabled" },
        reasoning_effort: "none",
        max_tokens: 1_600,
        stream: false,
      }),
      signal: AbortSignal.timeout(8_000),
    })
  } catch {
    return json({ error: "provider_unavailable" }, 503)
  }

  if (!upstream.ok) {
    // Do not pass provider messages to the app: they can contain sensitive
    // operational details and are not actionable for the user.
    return json({ error: "provider_rejected_request" }, 502)
  }

  let completion: DeepSeekResponse
  try {
    completion = await upstream.json()
  } catch {
    return json({ error: "provider_invalid_response" }, 502)
  }

  const content = completion.choices?.[0]?.message?.content
  if (!content) {
    return json({ error: "provider_empty_response" }, 502)
  }

  try {
    const candidate = JSON.parse(content)
    return json(validateResult(candidate, transcript))
  } catch {
    return json({ error: "provider_invalid_json" }, 502)
  }
})

const systemPrompt = `
Ты — семантический парсер записей Norka, версия norka-voice-v4.
Твоя задача — превратить разговорную русскую речь в одну или несколько самостоятельных записей.
Возвращай только валидный JSON без markdown и пояснений.

Схема JSON:
{
  "entries": [{
    "sourceText": "часть исходной речи, относящаяся к записи",
    "kind": "reminder|event",
    "title": "короткое понятное название",
    "details": "важный контекст или null",
    "dueDate": "ISO 8601 с часовым поясом или null",
    "endDate": "ISO 8601 окончания события или null",
    "reminderOffsets": [минуты до срока],
    "confidence": "low|medium|high",
    "ambiguities": ["missingDate"|"ambiguousDate"|"ambiguousTime"|"unclearReference"|"emptyTitle"]
  }],
  "linkGroups": [{"members": [0, 1], "confidence": "high", "evidence": "дословный фрагмент речи, явно связывающий обе записи"}]
}

Правила:
1. Создавай отдельные entries только для самостоятельных намерений: например «записаться к врачу и оплатить интернет» — две записи; «зайти в магазин и купить молоко» — одна запись с общей целью. Исправление «нет, лучше...» заменяет предыдущую версию, а не создаёт новую запись. Ничего не теряй и не дублируй. Максимум 6 записей.
2. Не выдумывай факты, дату или время. Разрешай относительные даты от referenceDate в timeZone. Для каждой записи назначай собственный срок. Общий срок распространяется на перечисленные записи, только если это явно следует из речи.
3. kind=reminder для действия/задачи; kind=event для встречи, вебинара, дня рождения, концерта и другого события, которое происходит. У события dueDate — начало; endDate — только если явно назван конец. Если начало события неясно, оставь dueDate=null, не подставляй выдуманное время.
4. Заголовок — естественная русская фраза из 2–8 слов, с прописной буквы и без точки в конце. Для напоминания — действие, для события — название.
5. Убирай приветствия, повторы, оговорки и вводные слова: «слушай», «короче», «в общем», «получается», «мне нужно», «надо не забыть», «напомни мне». Если пользователь исправил себя, используй последнюю версию.
6. Не помещай в заголовок дату, время, причину и второстепенные детали. Не превращай речь в канцелярит и не меняй смысл.
7. В details оставляй только полезный контекст: причину, цель, уточнение, адрес, человека или условие. Пиши 1–2 коротких законченных предложения, не повторяющих заголовок. Если полезного контекста нет, details=null.
8. Если срока нет, dueDate=null, confidence не выше medium, ambiguities содержит missingDate.
9. Части дня и границы трактуй строго по personalSchedule: «утром»=morning, «к/до начала работы»=workStarts, «в/к/до обеда»=начало lunch, «после обеда»=конец lunch, «после работы» и «до конца рабочего дня»=workEnds, «к/до вечера» и «вечером»=evening. Такие выражения задают dueDate и не должны попадать в details.
10. Ночь 00:00–03:00 после вечерней речи относится к следующему календарному дню. Явные 04:00 и 05:00 оставляй как раннее утро указанного дня.
11. "Напомни за час/день/неделю" не меняет dueDate. Оно задаёт reminderOffsets: допустимы только 0,5,15,30,60,1440,2880,10080.
12. Если пользователь назвал срок, но не просил отдельное предварительное уведомление, reminderOffsets=[] — приложение применит его настройку по умолчанию.
13. Даты возвращай в ISO 8601 с числовым смещением часового пояса.
14. confidence=high только если содержание и срок однозначны; medium — если содержание понятно, но срок отсутствует или приблизителен; low — если неясен смысл.
15. ambiguities описывает только реальную неоднозначность: ambiguousDate — неясен день, ambiguousTime — день понятен, но неясно время, unclearReference — неясен объект действия.
16. sourceText для каждой записи — конкретные слова пользователя об этой записи. Не добавляй в него текст из другой записи.
17. personalExamples — подтверждённые примеры стиля одной записи, не образцы числа записей. Не копируй их факты и абсолютные даты; пересчитывай срок от текущего referenceDate.
18. linkGroups — необязательные общие группы ТОЛЬКО новых entries, members — индексы с нуля. Связывай 2–6 самостоятельных записей лишь при явной общей цели или прямой просьбе связать. Например, событие «вебинар» и задача «отправить заявку, чтобы попасть на этот вебинар» образуют группу. Одна запись может быть только в одной группе. evidence — точная цитата из transcript, объясняющая связь, confidence всегда high. При сомнении верни linkGroups=[].
19. Само по себе перечисление, одинаковая дата, тема, человек, слова «потом» или «после этого» НЕ означают связь. «Завтра купить молоко и оплатить интернет» — отдельные записи без группы. «Зайти в магазин и купить молоко» остаётся ОДНОЙ записью, не разбивай её ради связи. Не придумывай дополнительные записи, сроки, зависимость выполнения или автоматический перенос дат ради группировки. Если есть несколько независимых групп, верни их раздельно.

Примеры. Во всех примерах referenceDate=2026-09-21T12:00:00+04:00, timeZone=Europe/Samara.

Вход: «Слушай, завтра после работы мне нужно отправить заявку на вебинар, потому что регистрация закрывается вечером»
JSON:
{"entries":[{"sourceText":"завтра после работы мне нужно отправить заявку на вебинар, потому что регистрация закрывается вечером","kind":"reminder","title":"Отправить заявку на вебинар","details":"Регистрация закрывается вечером.","dueDate":"2026-09-22T18:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]}]}

Вход: «Позвони Анне, нет, лучше напиши ей в понедельник утром и уточни какие документы нужны»
JSON:
{"entries":[{"sourceText":"лучше напиши ей в понедельник утром и уточни какие документы нужны","kind":"reminder","title":"Написать Анне","details":"Уточнить, какие документы нужны.","dueDate":"2026-09-28T08:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]}]}

Вход: «В пятницу в три оплатить интернет, напомни ещё за час»
JSON:
{"entries":[{"sourceText":"В пятницу в три оплатить интернет, напомни ещё за час","kind":"reminder","title":"Оплатить интернет","details":null,"dueDate":"2026-09-25T15:00:00+04:00","endDate":null,"reminderOffsets":[60],"confidence":"high","ambiguities":[]}]}

Вход: «Завтра до обеда надо отправить отчет клиенту, чтобы он успел посмотреть»
JSON:
{"entries":[{"sourceText":"Завтра до обеда надо отправить отчет клиенту, чтобы он успел посмотреть","kind":"reminder","title":"Отправить отчет клиенту","details":"Чтобы клиент успел посмотреть.","dueDate":"2026-09-22T13:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]}]}

Вход: «Короче надо не забыть купить фильтр для воды, старый уже совсем плохо работает»
JSON:
{"entries":[{"sourceText":"купить фильтр для воды, старый уже совсем плохо работает","kind":"reminder","title":"Купить фильтр для воды","details":"Старый фильтр уже плохо работает.","dueDate":null,"endDate":null,"reminderOffsets":[],"confidence":"medium","ambiguities":["missingDate"]}]}

Вход: «Завтра в девять оплатить интернет и в пятницу в семь вечера вебинар по дизайну»
JSON:
{"entries":[{"sourceText":"Завтра в девять оплатить интернет","kind":"reminder","title":"Оплатить интернет","details":null,"dueDate":"2026-09-22T09:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]},{"sourceText":"в пятницу в семь вечера вебинар по дизайну","kind":"event","title":"Вебинар по дизайну","details":null,"dueDate":"2026-09-25T19:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]}],"linkGroups":[]}

Вход: «В пятницу в семь вечера вебинар по дизайну. Завтра до обеда отправить заявку, чтобы попасть на этот вебинар»
JSON:
{"entries":[{"sourceText":"В пятницу в семь вечера вебинар по дизайну","kind":"event","title":"Вебинар по дизайну","details":null,"dueDate":"2026-09-25T19:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]},{"sourceText":"Завтра до обеда отправить заявку, чтобы попасть на этот вебинар","kind":"reminder","title":"Отправить заявку на вебинар","details":null,"dueDate":"2026-09-22T13:00:00+04:00","endDate":null,"reminderOffsets":[],"confidence":"high","ambiguities":[]}],"linkGroups":[{"members":[0,1],"confidence":"high","evidence":"отправить заявку, чтобы попасть на этот вебинар"}]}
`

function validateResult(value: unknown, transcript: string): { entries: VoiceResult[]; linkGroups: LinkGroup[] } {
  if (!isRecord(value) || !Array.isArray(value.entries) ||
    value.entries.length < 1 || value.entries.length > 6) {
    throw new Error("invalid_entries")
  }
  return {
    entries: value.entries.map((entry) => validateEntry(entry, transcript)),
    linkGroups: validateLinkGroups(value.linkGroups, value.entries.length, transcript),
  }
}

function validateEntry(value: unknown, transcript: string): VoiceResult {
  if (!isRecord(value)) throw new Error("invalid_result")

  const sourceText = typeof value.sourceText === "string" && value.sourceText.trim()
    ? value.sourceText.trim().slice(0, 1_000)
    : transcript
  const kind = value.kind === "event" ? "event" : "reminder"

  const rawTitle = typeof value.title === "string" ? value.title.trim() : ""
  if (!rawTitle || rawTitle.length > 240) throw new Error("invalid_title")

  const details = typeof value.details === "string" && value.details.trim()
    ? value.details.trim().slice(0, 2_000)
    : null

  let dueDate: string | null = null
  if (typeof value.dueDate === "string" && value.dueDate.trim()) {
    const date = new Date(value.dueDate)
    if (Number.isNaN(date.getTime())) throw new Error("invalid_date")
    dueDate = date.toISOString()
  }
  let endDate: string | null = null
  if (kind === "event" && typeof value.endDate === "string" && value.endDate.trim()) {
    const date = new Date(value.endDate)
    if (Number.isNaN(date.getTime())) throw new Error("invalid_end_date")
    endDate = date.toISOString()
  }
  if (endDate && (!dueDate || endDate < dueDate)) throw new Error("invalid_range")

  const reminderOffsets = Array.isArray(value.reminderOffsets)
    ? [...new Set(value.reminderOffsets
      .filter((item): item is number => Number.isInteger(item) && supportedReminderOffsets.has(item)))]
      .sort((left, right) => left - right)
    : []

  const confidence = value.confidence === "high" || value.confidence === "medium"
    ? value.confidence
    : "low"

  const allowedAmbiguities = new Set<VoiceAmbiguity>([
    "missingDate",
    "ambiguousDate",
    "ambiguousTime",
    "unclearReference",
    "multipleActions",
    "emptyTitle",
  ])
  const ambiguities = Array.isArray(value.ambiguities)
    ? [...new Set(value.ambiguities.filter(
      (item): item is VoiceAmbiguity =>
        typeof item === "string" && allowedAmbiguities.has(item),
    ))]
    : []

  if (!dueDate && !ambiguities.includes("missingDate")) {
    ambiguities.push("missingDate")
  }

  return {
    sourceText,
    kind,
    title: rawTitle,
    details,
    dueDate,
    endDate,
    reminderOffsets: dueDate ? reminderOffsets : [],
    confidence,
    ambiguities,
  }
}

function sanitizeExamples(value: unknown): VoiceLearningExample[] {
  if (!Array.isArray(value)) return []

  return value.slice(0, 3).flatMap((item): VoiceLearningExample[] => {
    if (!isRecord(item)) return []
    const transcript = typeof item.transcript === "string" ? item.transcript.trim() : ""
    const title = typeof item.title === "string" ? item.title.trim() : ""
    const referenceDate = typeof item.referenceDate === "string" ? item.referenceDate : ""
    const timeZone = typeof item.timeZone === "string" ? item.timeZone : ""
    if (!transcript || transcript.length > 1_000 || !title || title.length > 240) return []
    if (Number.isNaN(new Date(referenceDate).getTime()) || !isValidTimeZone(timeZone)) return []

    const details = typeof item.details === "string" && item.details.trim()
      ? item.details.trim().slice(0, 1_000)
      : null
    const dueDate = typeof item.dueDate === "string" && !Number.isNaN(new Date(item.dueDate).getTime())
      ? new Date(item.dueDate).toISOString()
      : null
    return [{ transcript, title, details, dueDate, referenceDate, timeZone }]
  })
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function bearerToken(authorization: string | null): string | null {
  if (!authorization?.startsWith("Bearer ")) return null
  const token = authorization.slice("Bearer ".length).trim()
  return token || null
}

function isAuthenticatedUserToken(token: string): boolean {
  const segments = token.split(".")
  if (segments.length !== 3) return false

  try {
    const normalized = segments[1].replace(/-/g, "+").replace(/_/g, "/")
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")
    const payload = JSON.parse(atob(padded))
    return isRecord(payload) &&
      payload.role === "authenticated" &&
      typeof payload.sub === "string" &&
      payload.sub.length > 0
  } catch {
    return false
  }
}

function isValidTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("ru-RU", { timeZone: value }).format()
    return true
  } catch {
    return false
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  })
}
