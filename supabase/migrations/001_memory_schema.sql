-- Memory: private user profiles and offline-first tasks.
-- Run this once in the Supabase SQL Editor for the project used by the app.

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    locale text not null default 'ru_RU',
    time_zone text not null default 'Europe/Samara',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.tasks (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null check (char_length(title) between 1 and 1000),
    due_at timestamptz,
    notifications_enabled boolean not null default false,
    is_completed boolean not null default false,
    completed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);

create index if not exists tasks_user_updated_idx
    on public.tasks(user_id, updated_at desc);

alter table public.profiles enable row level security;
alter table public.tasks enable row level security;

revoke all on table public.profiles from anon;
revoke all on table public.tasks from anon;
grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.tasks to authenticated;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
    on public.profiles for select to authenticated
    using ((select auth.uid()) = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
    on public.profiles for update to authenticated
    using ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);

drop policy if exists "Users can read own tasks" on public.tasks;
create policy "Users can read own tasks"
    on public.tasks for select to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own tasks" on public.tasks;
create policy "Users can insert own tasks"
    on public.tasks for insert to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update own tasks" on public.tasks;
create policy "Users can update own tasks"
    on public.tasks for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete own tasks" on public.tasks;
create policy "Users can delete own tasks"
    on public.tasks for delete to authenticated
    using ((select auth.uid()) = user_id);

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
    insert into public.profiles (id)
    values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists create_profile_after_signup on auth.users;
create trigger create_profile_after_signup
    after insert on auth.users
    for each row execute function public.create_profile_for_new_user();
