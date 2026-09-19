-- Multiple reminders per task and a synced default reminder lead time.

alter table public.profiles
    add column if not exists default_reminder_minutes integer not null default 0;

alter table public.tasks
    add column if not exists reminder_offsets integer[] not null default '{}';

-- Preserve the previous behaviour for existing tasks that had notifications enabled.
update public.tasks
set reminder_offsets = array[0]
where notifications_enabled = true
  and cardinality(reminder_offsets) = 0;
