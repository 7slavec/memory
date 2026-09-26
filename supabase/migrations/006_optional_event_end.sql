alter table public.tasks
    drop constraint if exists tasks_event_range_check;

alter table public.tasks
    add constraint tasks_event_range_check
    check (
        entry_kind = 'reminder'
        or (
            due_at is not null
            and (end_at is null or end_at > due_at)
        )
    );
