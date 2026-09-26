alter table public.tasks
    add column if not exists entry_kind text not null default 'reminder',
    add column if not exists end_at timestamptz;

alter table public.tasks
    drop constraint if exists tasks_entry_kind_check;

alter table public.tasks
    add constraint tasks_entry_kind_check
    check (entry_kind in ('reminder', 'event'));

alter table public.tasks
    drop constraint if exists tasks_event_range_check;

alter table public.tasks
    add constraint tasks_event_range_check
    check (
        entry_kind = 'reminder'
        or (due_at is not null and end_at is not null and end_at > due_at)
    );

alter table public.profiles
    add column if not exists default_entry_kind text not null default 'reminder';

alter table public.profiles
    drop constraint if exists profiles_default_entry_kind_check;

alter table public.profiles
    add constraint profiles_default_entry_kind_check
    check (default_entry_kind in ('reminder', 'event'));
