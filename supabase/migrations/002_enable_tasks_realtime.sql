-- Enables database-originated live updates in addition to the app's Realtime broadcasts.
-- Safe to run more than once in the Supabase SQL Editor.

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'tasks'
    ) then
        alter publication supabase_realtime add table public.tasks;
    end if;
end
$$;
