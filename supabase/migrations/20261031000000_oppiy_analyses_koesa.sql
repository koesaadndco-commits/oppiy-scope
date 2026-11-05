-- OPPIY SCOPE を Supabase プロジェクト「KOESA Project」(ibtpidqkcxmotlanfgsy)に統合。
-- 旧プロジェクト oppiy-scope(xnjcanoibshixxcjejii)は無料枠の「有効プロジェクト2つまで」に掛かって停止したため、
-- 社内の他アプリと同じプロジェクトに同居させる。共有プロジェクトなので、このアプリのテーブル・関数名はすべて oppiy_ 始まり。
-- 20261009000000_analyses.sql と 20261010000000_tenants.sql(旧プロジェクト向け)を1本にまとめた内容。
-- KOESA Project には apply 済み(oppiy_analyses_merge_from_oppiy_scope / oppiy_tenants_align_with_app)。

create table public.oppiy_tenants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text unique,
  plan        text not null default 'trial',      -- trial / standard / pro など(課金は別途)
  status      text not null default 'active',     -- active / suspended
  created_at  timestamptz not null default now()
);

create table public.oppiy_memberships (
  tenant_id   uuid not null references public.oppiy_tenants (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        text not null default 'member' check (role in ('owner', 'admin', 'member')),
  created_at  timestamptz not null default now(),
  primary key (tenant_id, user_id)
);
create index oppiy_memberships_user_id_idx on public.oppiy_memberships (user_id);

-- analyses: 1レコード = 1解析。中身(scores, dancers, angles, compare …)は data(JSON)に丸ごと入れる。動画そのものは保存しない。
create table public.oppiy_analyses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tenant_id   uuid not null references public.oppiy_tenants (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  data        jsonb not null
);
create index oppiy_analyses_created_at_idx on public.oppiy_analyses (created_at desc);
create index oppiy_analyses_user_id_idx on public.oppiy_analyses (user_id);
create index oppiy_analyses_tenant_id_idx on public.oppiy_analyses (tenant_id, created_at desc);

create or replace function public.oppiy_set_updated_at()
returns trigger language plpgsql set search_path to '' as $$
begin new.updated_at = now(); return new; end $$;
create trigger oppiy_analyses_set_updated_at
  before update on public.oppiy_analyses
  for each row execute function public.oppiy_set_updated_at();

-- 自分が属するテナント一覧(RLS の中から呼ぶので security definer)
create or replace function public.oppiy_my_tenant_ids()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select tenant_id from public.oppiy_memberships where user_id = (select auth.uid())
$$;

-- 記録を入れるとき tenant_id が無ければ、所属テナントの1つ目を入れる
create or replace function public.oppiy_set_analysis_tenant()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tenant_id is null then
    select tenant_id into new.tenant_id from public.oppiy_memberships where user_id = (select auth.uid()) order by created_at limit 1;
  end if;
  return new;
end $$;
create trigger oppiy_analyses_set_tenant before insert on public.oppiy_analyses
  for each row execute function public.oppiy_set_analysis_tenant();

-- RLS: 自分が属するテナントの記録だけ。匿名・他アプリのユーザーは何も見えない
alter table public.oppiy_tenants enable row level security;
alter table public.oppiy_memberships enable row level security;
alter table public.oppiy_analyses enable row level security;

create policy oppiy_tenants_select_member on public.oppiy_tenants for select to authenticated
  using (id in (select public.oppiy_my_tenant_ids()));

create policy oppiy_memberships_select_own_or_admin on public.oppiy_memberships for select to authenticated
  using (user_id = (select auth.uid()) or tenant_id in (select m.tenant_id from public.oppiy_memberships m where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin')));

create policy oppiy_analyses_select_tenant on public.oppiy_analyses for select to authenticated
  using (tenant_id in (select public.oppiy_my_tenant_ids()));
create policy oppiy_analyses_insert_tenant on public.oppiy_analyses for insert to authenticated
  with check (user_id = (select auth.uid()) and tenant_id in (select public.oppiy_my_tenant_ids())
              and exists (select 1 from public.oppiy_tenants t where t.id = tenant_id and t.status = 'active'));
create policy oppiy_analyses_update_tenant on public.oppiy_analyses for update to authenticated
  using (tenant_id in (select public.oppiy_my_tenant_ids())) with check (tenant_id in (select public.oppiy_my_tenant_ids()));
create policy oppiy_analyses_delete_tenant on public.oppiy_analyses for delete to authenticated
  using (tenant_id in (select public.oppiy_my_tenant_ids()));
