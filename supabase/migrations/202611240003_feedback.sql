-- Create feedback and feedback_likes tables with RLS and owner policies.

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default '',
  content text not null check (char_length(trim(content)) between 1 and 1000),
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.feedback_likes (
  feedback_id uuid not null references public.feedback(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (feedback_id, user_id)
);

create index if not exists feedback_created_at_idx on public.feedback (created_at desc);
create index if not exists feedback_user_id_idx on public.feedback (user_id);
create index if not exists feedback_likes_feedback_id_idx on public.feedback_likes (feedback_id);

alter table public.feedback enable row level security;
alter table public.feedback_likes enable row level security;

revoke all on public.feedback, public.feedback_likes from anon;
grant select, insert, update, delete on public.feedback, public.feedback_likes to authenticated;

-- Policies for feedback
drop policy if exists "feedback_read" on public.feedback;
create policy "feedback_read" on public.feedback for select to authenticated
  using (visibility = 'public' or user_id = (select auth.uid()));

drop policy if exists "feedback_insert" on public.feedback;
create policy "feedback_insert" on public.feedback for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "feedback_update" on public.feedback;
create policy "feedback_update" on public.feedback for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "feedback_delete" on public.feedback;
create policy "feedback_delete" on public.feedback for delete to authenticated
  using (user_id = (select auth.uid()));

-- Policies for feedback_likes (prevents duplicate likes via primary key constraint)
drop policy if exists "feedback_likes_read" on public.feedback_likes;
create policy "feedback_likes_read" on public.feedback_likes for select to authenticated
  using (true);

drop policy if exists "feedback_likes_insert" on public.feedback_likes;
create policy "feedback_likes_insert" on public.feedback_likes for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "feedback_likes_delete" on public.feedback_likes;
create policy "feedback_likes_delete" on public.feedback_likes for delete to authenticated
  using (user_id = (select auth.uid()));

-- Seed initial suggestions if table is empty and a user exists
do $$
declare
  seed_user uuid;
begin
  select id into seed_user from auth.users order by created_at asc limit 1;
  if seed_user is not null then
    if not exists (select 1 from public.feedback) then
      insert into public.feedback (user_id, author_name, content, visibility) values
        (seed_user, 'Planova', 'Start with the tasks you can realistically finish today.', 'public'),
        (seed_user, 'Planova', 'Leave a little room between tasks so you do not have to rush.', 'public'),
        (seed_user, 'Planova', 'Add a short break between focus sessions.', 'public');
    end if;
  end if;
end;
$$;
