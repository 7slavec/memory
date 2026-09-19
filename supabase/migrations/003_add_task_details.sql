-- Norka: optional description/context for an existing tasks table.
-- Safe to run more than once.

alter table public.tasks
    add column if not exists details text;

alter table public.tasks
    drop constraint if exists tasks_details_length_check;

alter table public.tasks
    add constraint tasks_details_length_check
    check (details is null or char_length(details) <= 4000);
