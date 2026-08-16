-- =============================================================================
-- compteurs_paie_periodes.sql
-- Date       : 2026-08-16
-- Rôle       : compteurs X / Y par période — alimente l'affichage « X / Y
--              validés » des cartes de l'onglet Paie (admin-v2.html,
--              renderEntetePaie) ET la garde de clôture (cloturerPeriode :
--              clôture autorisée seulement si Y > 0 et X === Y).
--              Renvoie (periode_id text, x integer, y integer).
--
-- Définitions :
--   Y = count(distinct collab_id) sur `paie_detail` pour la période
--       (collaborateurs ayant au moins une ligne importée).
--   X = count(distinct collab_id) sur `recap_paie` où
--       statut_validation = 'valide' (collaborateurs validés).
--
-- Pourquoi une RPC : `calculerCountsPaie` rapatriait TOUTES les lignes des deux
--              tables (~20 000 lignes/an, volume croissant) pour n'en tirer que
--              deux comptages. Paginée (fetchAllPages), donc sans troncature —
--              mais le mur était repoussé, pas supprimé. L'agrégation en base
--              renvoie une poignée de lignes.
--
-- ⚠️ Le `with ids as (select unnest(...))` garantit UNE LIGNE PAR IDENTIFIANT
--    DEMANDÉ, même sans aucune donnée (period vide → x=0, y=0). Sans lui, une
--    période sans ligne serait ABSENTE du résultat.
--
-- ⚠️ `count(distinct collab_id)` est OBLIGATOIRE : il reproduit les `Set` du
--    front. Un `count(*)` compterait plusieurs lignes par collaborateur
--    (plusieurs jours dans paie_detail).
--
-- ⚠️ CREATE FUNCTION re-grante EXECUTE à `public` À CHAQUE création → le revoke
--    ci-dessous est OBLIGATOIRE après chaque `create or replace`.
--
-- Droits : `anon` a l'EXÉCUTION (comme `derniere_saisie_par_collab`) — la RPC
--          est appelée DIRECTEMENT par le front (clé publishable), sans Edge.
--          Lecture non nominative (des comptages), pas de donnée sensible.
--
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

create or replace function compteurs_paie_periodes(p_periode_ids text[])
returns table (
  periode_id  text,
  x           integer,
  y           integer
)
language sql
stable
as $$
  with ids as (
    select unnest(p_periode_ids) as periode_id
  ),
  y_counts as (
    select pd.periode_id, count(distinct pd.collab_id) as n
    from paie_detail pd
    where pd.periode_id = any(p_periode_ids)
    group by pd.periode_id
  ),
  x_counts as (
    select rp.periode_id, count(distinct rp.collab_id) as n
    from recap_paie rp
    where rp.periode_id = any(p_periode_ids)
      and rp.statut_validation = 'valide'
    group by rp.periode_id
  )
  select i.periode_id,
         coalesce(x.n, 0)::integer,
         coalesce(y.n, 0)::integer
  from ids i
  left join x_counts x on x.periode_id = i.periode_id
  left join y_counts y on y.periode_id = i.periode_id;
$$;

revoke execute on function compteurs_paie_periodes(text[]) from public;
grant  execute on function compteurs_paie_periodes(text[]) to anon;
