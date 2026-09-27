# Norka: working entry point

## Read only the relevant slice

- Start with `docs/SYSTEM.md`: service map, component ownership, accepted design rules, and verification protocol.
- Read `docs/AUDIT-2026-09-27.md` for known gaps and the staged refactor. An open finding is not permission to change product behavior silently.
- `PRODUCT_ROADMAP.md` owns feature order; `EVENTS_PRODUCT_SPEC.md` is historical event implementation context. Where older text conflicts with the latest approved rules in SYSTEM.md, flag the conflict instead of guessing.
- Locate a symbol with `rg -n` and read that section. Do not load the whole root screen for a calendar, chip, or card change.

## Change boundaries

- User-approved Norka patterns take precedence over generic design skill suggestions. No additional card variants, helper subtitles, new navigation patterns, or visual redesign during structural extraction.
- Shared visuals belong in `Memory/DesignSystem`; screen-specific composition/state in `Memory/Features`; interpretation rules in `Memory/Domain/Interpretation`. Existing root files are migration debt, not a pattern for new code.
- Shared components accept values and actions; they must not save, synchronize, request permissions, or own app navigation. `MemoryItemRow` currently reads `Item` but has no write responsibility.
- A complete editor replaces its page/header. Never embed a full screen inside the composer or below another full screen's header.
- Separate mechanical extraction from behavior changes. Preserve state ownership, identity, keyboard focus, platform guards, and save/undo semantics while moving declarations.
- Do not migrate SwiftData/Supabase, clear data, reset accounts, or deploy backend code as a side effect of UI refactoring.

## Completion evidence

- Use `scripts/verify-local.sh` for Mac unit tests + iOS compile; optional `--ui` adds the isolated Mac multi-record UI scenario. See SYSTEM.md for limits.
- A build is not a visual or device check. Report build, test, installation, launch, and manual verification separately.
- Run `git diff --check`. Review staged paths and secrets before committing/pushing. Never include `SupabaseConfig.plist`, `.env`, local stores, Voice Lab user samples, signing material, or `supabase/.temp`.
- Keep checkpoint and structural commits separate. Do not force-push or revert unrelated work.
