create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 60),
  avatar_data text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.plans (
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_date date not null,
  revision integer not null default 1 check (revision > 0),
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, plan_date)
);

create table if not exists public.settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null check (key in ('time_format')),
  value text not null,
  primary key (user_id, key)
);

alter table public.profiles enable row level security;
alter table public.plans enable row level security;
alter table public.settings enable row level security;

revoke all on public.profiles, public.plans, public.settings from anon;
grant select, insert, update, delete on public.profiles, public.plans, public.settings to authenticated;

create policy "profiles_owner_all" on public.profiles for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "plans_owner_all" on public.plans for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "settings_owner_all" on public.settings for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.create_planova_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(user_id, name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1)))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_planova_user_created on auth.users;
create trigger on_planova_user_created after insert on auth.users
for each row execute function public.create_planova_profile();

insert into public.profiles(user_id, name)
select id, coalesce(nullif(trim(raw_user_meta_data ->> 'name'), ''), split_part(email, '@', 1))
from auth.users on conflict (user_id) do nothing;

