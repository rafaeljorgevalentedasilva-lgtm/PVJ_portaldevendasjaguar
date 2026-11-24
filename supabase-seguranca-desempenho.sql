-- PORTAL DE VENDAS JAGUAR — MIGRAÇÃO COMPLEMENTAR DE SEGURANÇA E DESEMPENHO
-- Projeto Supabase: hgvojvbxuxgpcehrkgsj
-- Esta migração é aditiva/conservadora. Não remove tabelas nem dados.
-- Antes de executar em produção, faça backup do banco.

begin;

-- 1) Índices para filtros e ordenação mais usados no catálogo público.
create index if not exists lojas_ativas_nome_idx
  on public."Lojas" (nome, id)
  where ativo = true;

create index if not exists lojas_categoria_ativas_nome_idx
  on public."Lojas" (categoria, nome, id)
  where ativo = true;

-- 2) Índices para estatísticas e avaliações.
create index if not exists loja_eventos_loja_tipo_data_idx
  on public.loja_eventos (loja_id, tipo, created_at desc);

create index if not exists loja_avaliacoes_loja_nota_idx
  on public.loja_avaliacoes (loja_id, nota);

-- 3) Reduzir privilégios diretos do papel anon.
-- O visitante só precisa ler lojas ativas e categorias.
revoke all privileges on table public."Lojas" from public, anon;
grant select on table public."Lojas" to anon;

revoke all privileges on table public.categorias from public, anon;
grant select on table public.categorias to anon;

-- Escrita de lojas/categorias somente por usuários autenticados.
-- As políticas RLS existentes continuam sendo a barreira que restringe
-- essas operações ao administrador autorizado.
grant select, insert, update, delete on table public."Lojas" to authenticated;
grant select, insert, update, delete on table public.categorias to authenticated;

-- Tabelas internas: sem acesso anônimo direto.
revoke all privileges on table public.admin_users from public, anon;
grant select on table public.admin_users to authenticated;

revoke all privileges on table public.loja_eventos from public, anon;
grant select on table public.loja_eventos to authenticated;

revoke all privileges on table public.loja_avaliacoes from public, anon, authenticated;

-- O navegador não precisa de permissões sobre sequências.
revoke all privileges on all sequences in schema public from public, anon;

-- O painel administrativo pode precisar das sequências para inserir lojas
-- e categorias via PostgREST; a RLS continua limitando as tabelas.
grant usage, select on all sequences in schema public to authenticated;

-- 4) Limitar uploads no bucket de imagens. O portal converte imagens para WebP.
-- Se o bucket não existir, esta atualização não altera nada.
update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg','image/png','image/webp']::text[]
where id = 'fotos_lojas';

commit;

-- 5) Atualizar o cache de metadados do PostgREST.
notify pgrst, 'reload schema';

-- ATENÇÃO:
-- Este arquivo não substitui a auditoria das tabelas assinaturas_lojas e
-- historico_assinaturas. O SQL fornecido no projeto não contém suas definições
-- nem suas políticas RLS. Não publique o painel de assinaturas até confirmar
-- no Supabase que essas tabelas permitem leitura/escrita apenas a admins.
--
-- Também é necessário revisar as políticas antigas já existentes no Supabase.
-- Políticas permissivas adicionais podem ampliar o acesso, pois políticas RLS
-- permissivas são combinadas por OR. Esta migração reduz grants de anon, mas
-- não apaga políticas antigas de authenticated.
