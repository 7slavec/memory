-- Additive, symmetric links. Neither dates nor completion propagate.
begin;
create table if not exists public.task_links (
    id text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    first_id uuid not null references public.tasks(id) on delete cascade,
    second_id uuid not null references public.tasks(id) on delete cascade,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint task_links_order check (first_id::text < second_id::text),
    constraint task_links_key check (id = first_id::text || '_' || second_id::text)
);
create index if not exists task_links_owner on public.task_links(user_id);
create index if not exists task_links_first on public.task_links(first_id);
create index if not exists task_links_second on public.task_links(second_id);
alter table public.task_links enable row level security;
drop policy if exists "Own record links" on public.task_links;
create policy "Own record links" on public.task_links for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
grant select, insert, update on public.task_links to authenticated;
revoke delete on public.task_links from authenticated;

create or replace function public.validate_record_link() returns trigger
language plpgsql set search_path = '' as $$
declare
    first_owner uuid; second_owner uuid;
    first_deleted timestamptz; second_deleted timestamptz;
begin
    if TG_OP = 'UPDATE' then
        if new.id <> old.id or new.user_id <> old.user_id or new.first_id <> old.first_id or new.second_id <> old.second_id then
            raise exception 'Link endpoints are immutable';
        end if;
        -- Ignore stale writes, including a stale active copy after an offline unlink.
        if new.updated_at < old.updated_at or
           (new.updated_at = old.updated_at and old.deleted_at is not null and new.deleted_at is null) then
            return null;
        end if;
    end if;
    select user_id, deleted_at into first_owner, first_deleted from public.tasks where id = new.first_id for share;
    select user_id, deleted_at into second_owner, second_deleted from public.tasks where id = new.second_id for share;
    if first_owner is distinct from new.user_id or second_owner is distinct from new.user_id then
        raise exception 'Both records must belong to the same account';
    end if;
    if (first_deleted is not null or second_deleted is not null) and new.deleted_at is null then
        new.updated_at := greatest(clock_timestamp(), new.updated_at + interval '3 milliseconds');
        new.deleted_at := new.updated_at;
    end if;
    return new;
end $$;
drop trigger if exists validate_record_link on public.task_links;
create trigger validate_record_link before insert or update on public.task_links
    for each row execute function public.validate_record_link();

create or replace function public.unlink_deleted_record() returns trigger
language plpgsql set search_path = '' as $$
begin
    if new.deleted_at is not null and old.deleted_at is null then
        update public.task_links
        set updated_at = greatest(clock_timestamp(), updated_at + interval '3 milliseconds'),
            deleted_at = greatest(clock_timestamp(), updated_at + interval '3 milliseconds')
        where user_id = new.user_id and (first_id = new.id or second_id = new.id) and deleted_at is null;
    end if;
    return new;
end $$;
drop trigger if exists unlink_deleted_record on public.tasks;
create trigger unlink_deleted_record after update of deleted_at on public.tasks
    for each row execute function public.unlink_deleted_record();
do $$ begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') and not exists (
        select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_links'
    ) then
        alter publication supabase_realtime add table public.task_links;
    end if;
end $$;
commit;
