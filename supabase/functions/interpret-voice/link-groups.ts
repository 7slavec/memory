export type LinkGroup = { members: number[]; confidence: "high"; evidence: string }

// Invalid optional metadata is dropped, not the useful voice entries.
export function validateLinkGroups(value: unknown, count: number, transcript: string): LinkGroup[] {
  if (!Array.isArray(value) || value.length > 3 || count < 2) return []
  const normalize = (text: string) => text.toLowerCase().replaceAll("ё", "е").trim().replace(/\s+/g, " ")
  const speech = normalize(transcript)
  const used = new Set<number>()
  const groups: LinkGroup[] = []
  for (const group of value) {
    if (!group || typeof group !== "object" || group.confidence !== "high" ||
        !Array.isArray(group.members) || group.members.length < 2 ||
        !group.members.every((id: unknown) => Number.isInteger(id) && Number(id) >= 0 && Number(id) < count) ||
        new Set(group.members).size !== group.members.length || typeof group.evidence !== "string") continue
    const evidence = normalize(group.evidence)
    if (evidence.length < 8 || !speech.includes(evidence)) continue
    if (group.members.some((id: number) => used.has(id))) return []
    group.members.forEach((id: number) => used.add(id))
    groups.push({ members: group.members, confidence: "high", evidence: group.evidence.trim() })
  }
  return groups
}
