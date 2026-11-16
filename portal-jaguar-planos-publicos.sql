-- PORTAL JAGUAR — preços públicos dos planos exibidos na página inicial
-- Execute no SQL Editor do Supabase.
-- A função expõe somente os dois valores comerciais necessários ao visitante.

create table if not exists public.configuracoes_assinatura (
  id integer primary key check (id = 1),
  vip_price numeric(12,2) not null default 20.00 check (vip_price >= 0),
  direct_discount_percent numeric(5,2) not null default 10.00
    check (direct_discount_percent >= 0 and direct_discount_percent <= 100),
  updated_at timestamptz not null default now()
);

insert into public.configuracoes_assinatura (id, vip_price, direct_discount_percent)
values (1, 20.00, 10.00)
on conflict (id) do nothing;

create or replace function public.configuracoes_precos_publicas()
returns table (
  vip_price numeric,
  direct_discount_percent numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.vip_price, c.direct_discount_percent
  from public.configuracoes_assinatura as c
  where c.id = 1
  limit 1;
$$;

revoke all on function public.configuracoes_precos_publicas() from public;
grant execute on function public.configuracoes_precos_publicas() to anon, authenticated;

notify pgrst, 'reload schema';
