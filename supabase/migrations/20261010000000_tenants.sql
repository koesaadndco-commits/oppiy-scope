-- テナント(スタジオ単位)でデータを分ける。
-- tenants: 契約の単位。memberships: どのユーザーがどのテナントに属するか(owner / admin / member)。
-- analyses.tenant_id: 記録の所属。RLS は「自分が属するテナントの記録だけ」。

create table public.tenants (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text unique,
  plan        text not null default 'trial',      -- trial / standard / pro など(課金は別途)
  status      text not null default 'active',     -- active / suspended
  created_at  timestamptz not null default now()
);

create table public.memberships (
  tenant_id   uuid not null references public.tenants (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        text not null default 'member' check (role in ('owner', 'admin', 'member')),
  created_at  timestamptz not null default now(),
  primary key (tenant_id, user_id)
);
create index memberships_user_id_idx on public.memberships (user_id);

alter table public.analyses add column tenant_id uuid references public.tenants (id) on delete cascade;
create index analyses_tenant_id_idx on public.analyses (tenant_id, created_at desc);

-- 自分が属するテナント一覧(RLS の中から呼ぶので security definer)
create or replace function public.my_tenant_ids()
returns setof uuid
language sql stable security definer
set search_path = ''
as $$ select tenant_id from public.memberships where user_id = auth.uid() $$;

-- 記録を入れるとき tenant_id が無ければ、所属テナントの1つ目を入れる
create or replace function public.set_analysis_tenant()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.tenant_id is null then
    select tenant_id into new.tenant_id from public.memberships where user_id = auth.uid() order by created_at limit 1;
  end if;
  return new;
end;
$$;
create trigger analyses_set_tenant before insert on public.analyses
  for each row execute function public.set_analysis_tenant();

-- 既存データの引っ越し:既定テナントを作り、既存ユーザー全員を owner にし、既存の記録を所属させる
do $$
declare t uuid;
begin
  insert into public.tenants (name, slug) values ('KOESA', 'koesa') returning id into t;
  insert into public.memberships (tenant_id, user_id, role) select t, id, 'owner' from auth.users;
  update public.analyses set tenant_id = t where tenant_id is null;
end $$;
alter table public.analyses alter column tenant_id set not null;

-- RLS
alter table public.tenants enable row level security;
alter table public.memberships enable row level security;

create policy "tenants_select_member" on public.tenants for select to authenticated
  using (id in (select public.my_tenant_ids()));

create policy "memberships_select_own_or_admin" on public.memberships for select to authenticated
  using (user_id = (select auth.uid()) or tenant_id in (select m.tenant_id from public.memberships m where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin')));

drop policy "analyses_select_authenticated" on public.analyses;
drop policy "analyses_insert_authenticated" on public.analyses;
drop policy "analyses_update_authenticated" on public.analyses;
drop policy "analyses_delete_authenticated" on public.analyses;

create policy "analyses_select_tenant" on public.analyses for select to authenticated
  using (tenant_id in (select public.my_tenant_ids()));
create policy "analyses_insert_tenant" on public.analyses for insert to authenticated
  with check (user_id = (select auth.uid()) and tenant_id in (select public.my_tenant_ids())
              and exists (select 1 from public.tenants t where t.id = tenant_id and t.status = 'active'));
create policy "analyses_update_tenant" on public.analyses for update to authenticated
  using (tenant_id in (select public.my_tenant_ids())) with check (tenant_id in (select public.my_tenant_ids()));
create policy "analyses_delete_tenant" on public.analyses for delete to authenticated
  using (tenant_id in (select public.my_tenant_ids()));
