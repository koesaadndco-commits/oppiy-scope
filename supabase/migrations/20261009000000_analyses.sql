-- analyses: 1レコード = 1解析。中身(scores, dancers, angles, compare …)は data(JSON)に丸ごと入れる。
-- 動画そのものは保存しない。
create table public.analyses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  data        jsonb not null
);

create index analyses_created_at_idx on public.analyses (created_at desc);
create index analyses_user_id_idx on public.analyses (user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger analyses_set_updated_at
  before update on public.analyses
  for each row execute function public.set_updated_at();

-- RLS: ログイン済みユーザーだけが触れる。スタジオ内の共有ツールなので
-- 読み書きはログイン済み全員に許可し、匿名(anon)は何もできない。
-- 本人の記録だけに絞る場合は with check / using を (user_id = (select auth.uid())) に変える。
alter table public.analyses enable row level security;

create policy "analyses_select_authenticated"
  on public.analyses for select
  to authenticated
  using (true);

create policy "analyses_insert_authenticated"
  on public.analyses for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy "analyses_update_authenticated"
  on public.analyses for update
  to authenticated
  using (true)
  with check (true);

create policy "analyses_delete_authenticated"
  on public.analyses for delete
  to authenticated
  using (true);
