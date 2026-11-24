-- PORTAL DE VENDAS JAGUAR — PAGINAÇÃO REAL NO SUPABASE
-- Execute este arquivo no SQL Editor do projeto hgvojvbxuxgpcehrkgsj.
-- Faça um backup antes. A migração não apaga nem altera registros existentes.
-- Requer as funções/tabelas já usadas pelo portal:
-- public.assinaturas_publicas_lojas(), public.loja_avaliacoes,
-- public.loja_eventos e public.eh_admin().

begin;

-- Índice trigram acelera a pesquisa por trecho do nome/categoria (ILIKE %texto%).
create extension if not exists pg_trgm with schema extensions;
do $$
declare
  ext_schema text;
begin
  select n.nspname into ext_schema
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pg_trgm';
  if ext_schema is not null then
    execute format('create index if not exists lojas_nome_trgm_idx on public."Lojas" using gin (nome %I.gin_trgm_ops)', ext_schema);
    execute format('create index if not exists lojas_categoria_trgm_idx on public."Lojas" using gin (categoria %I.gin_trgm_ops)', ext_schema);
  end if;
end $$;

-- Índices que ajudam a ordenar e filtrar as lojas sem carregar tudo no navegador.
create index if not exists lojas_nome_id_idx
  on public."Lojas" (nome, id);

create index if not exists lojas_categoria_nome_id_idx
  on public."Lojas" (categoria, nome, id)
  where ativo = true;

create index if not exists loja_eventos_loja_tipo_data_idx
  on public.loja_eventos (loja_id, tipo, created_at desc);

create index if not exists loja_avaliacoes_loja_idx
  on public.loja_avaliacoes (loja_id);

-- Catálogo público paginado pelo PostgREST.
-- Pesquisa, categoria, plano, prioridade VIP/teste e avaliação são resolvidos no banco.
-- Retorna JSONB para preservar todos os campos públicos existentes de Lojas sem
-- presumir os tipos exatos das colunas opcionais (galeria, produtos, etc.).
create or replace function public.catalogo_publico_paginado(
  p_busca text default null,
  p_categoria text default null,
  p_plano text default null
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with planos as (
    select
      x.loja_id,
      lower(coalesce(x.modo_assinatura, '')) as modo
    from public.assinaturas_publicas_lojas() as x
  ),
  base as (
    select
      l.*,
      coalesce(p.modo, '') as modo_assinatura,
      coalesce(a.media, 0)::numeric as media,
      coalesce(a.total, 0)::bigint as total
    from public."Lojas" as l
    left join planos as p on p.loja_id = l.id
    left join lateral (
      select
        round(avg(av.nota)::numeric, 1) as media,
        count(*)::bigint as total
      from public.loja_avaliacoes as av
      where av.loja_id = l.id
    ) as a on true
    where l.ativo = true
      and (nullif(trim(p_busca), '') is null or l.nome ilike '%' || trim(p_busca) || '%' or coalesce(l.categoria, '') ilike '%' || trim(p_busca) || '%')
      and (nullif(trim(p_categoria), '') is null or l.categoria = trim(p_categoria))
      and (
        nullif(trim(p_plano), '') is null
        or (lower(trim(p_plano)) = 'sem' and coalesce(p.modo, '') not in ('vip', 'teste'))
        or lower(coalesce(p.modo, '')) = lower(trim(p_plano))
      )
  )
  select to_jsonb(b)
  from base as b
  order by
    case b.modo_assinatura when 'vip' then 0 when 'teste' then 1 else 2 end,
    b.media desc,
    b.total desc,
    b.nome asc,
    b.id asc;
$$;

revoke all on function public.catalogo_publico_paginado(text, text, text) from public;
grant execute on function public.catalogo_publico_paginado(text, text, text) to anon, authenticated;

-- Estatísticas somente das lojas visíveis na página atual do painel.
create or replace function public.estatisticas_lojas_por_ids(p_loja_ids bigint[])
returns table (
  loja_id bigint,
  acessos bigint,
  conversas bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    l.id,
    count(e.id) filter (where e.tipo = 'visita')::bigint,
    count(e.id) filter (where e.tipo = 'conversa')::bigint
  from public."Lojas" as l
  left join public.loja_eventos as e on e.loja_id = l.id
  where public.eh_admin()
    and l.id = any(coalesce(p_loja_ids, array[]::bigint[]))
  group by l.id;
$$;

revoke all on function public.estatisticas_lojas_por_ids(bigint[]) from public;
grant execute on function public.estatisticas_lojas_por_ids(bigint[]) to authenticated;

-- Avaliações somente das lojas exibidas no catálogo ou na página de detalhes.
create or replace function public.avaliacoes_publicas_lojas_por_ids(p_loja_ids bigint[])
returns table (
  loja_id bigint,
  media numeric,
  total bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    l.id,
    coalesce(round(avg(a.nota)::numeric, 1), 0::numeric),
    count(a.id)::bigint
  from public."Lojas" as l
  left join public.loja_avaliacoes as a on a.loja_id = l.id
  where l.ativo = true
    and l.id = any(coalesce(p_loja_ids, array[]::bigint[]))
  group by l.id;
$$;

revoke all on function public.avaliacoes_publicas_lojas_por_ids(bigint[]) from public;
grant execute on function public.avaliacoes_publicas_lojas_por_ids(bigint[]) to anon, authenticated;

notify pgrst, 'reload schema';
commit;
