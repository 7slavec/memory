# Подключение Supabase к Memory

1. Создать бесплатный проект на Supabase.
2. Открыть SQL Editor и выполнить `migrations/001_memory_schema.sql`.
3. В настройках проекта скопировать Project URL и Publishable key.
4. Скопировать `Memory/SupabaseConfig.example.plist` в
   `Memory/SupabaseConfig.plist` и заменить в копии `SUPABASE_URL` и
   `SUPABASE_PUBLISHABLE_KEY` на значения проекта. Локальный файл исключён из Git.

В приложение можно добавлять только Publishable key. Никогда не добавляйте
`service_role` key: он обходит защиту строк и предназначен только для сервера.

Пока значения не указаны, приложение продолжает полноценно работать локально.
