-- College Fair Checklist – new Supabase project schema
-- Run in Supabase Dashboard → SQL Editor → New query, then Run.
-- Replace with your new project; then set supabase_config.dart URL and anon key.

-- College fairs (top-level dropdown: name + date)
create table if not exists public.college_fairs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  fair_date date not null,
  created_at timestamptz not null default now()
);

-- Level 1: Groups within a college fair's checklist
create table if not exists public.checklist_groups (
  id uuid primary key default gen_random_uuid(),
  college_fair_id uuid not null references public.college_fairs(id) on delete cascade,
  title text not null,
  sort_order int not null default 0
);

-- Level 2: Items within a group (checkbox with label, or label + text field)
create table if not exists public.checklist_items (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.checklist_groups(id) on delete cascade,
  label text not null,
  item_type text not null check (item_type in ('checkbox', 'text')),
  sort_order int not null default 0,
  url text
);

-- Per-user completion/data (one row per user per item)
-- checkbox items: use is_complete; text items: use text_value
create table if not exists public.user_checklist (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.checklist_items(id) on delete cascade,
  is_complete boolean,
  text_value text,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(user_id, item_id)
);

-- Indexes for common lookups
create index if not exists idx_checklist_groups_college_fair on public.checklist_groups(college_fair_id);
create index if not exists idx_checklist_items_group on public.checklist_items(group_id);
create index if not exists idx_user_checklist_user on public.user_checklist(user_id);
create index if not exists idx_user_checklist_item on public.user_checklist(item_id);

-- RLS: authenticated users can read college fairs, groups, items
alter table public.college_fairs enable row level security;
create policy "Authenticated read college_fairs"
  on public.college_fairs for select to authenticated using (true);

alter table public.checklist_groups enable row level security;
create policy "Authenticated read checklist_groups"
  on public.checklist_groups for select to authenticated using (true);

alter table public.checklist_items enable row level security;
create policy "Authenticated read checklist_items"
  on public.checklist_items for select to authenticated using (true);

-- RLS: users can only read/write their own user_checklist rows
alter table public.user_checklist enable row level security;
create policy "Users read own user_checklist"
  on public.user_checklist for select to authenticated
  using (auth.uid() = user_id);
create policy "Users insert own user_checklist"
  on public.user_checklist for insert to authenticated
  with check (auth.uid() = user_id);
create policy "Users update own user_checklist"
  on public.user_checklist for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Optional: sample data for testing
-- insert into public.college_fairs (name, fair_date) values
--   ('Spring 2026 Fair', '2026-04-15'),
--   ('Fall 2026 Fair', '2026-10-01');
-- Then add groups and items via Dashboard or more inserts.
