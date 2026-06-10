-- =============================================================================
-- historique_contrats.sql
-- Date       : 2026-06-07
-- But        : Trace l'ÉVOLUTION du contexte contractuel de chaque
--              collaborateur dans le temps. Une ligne PAR CHANGEMENT de
--              contrat (événement rare). date_fin NULL = contrat en cours.
--              La table `collaborateurs` conserve l'état COURANT du contrat ;
--              `historique_contrats` conserve l'évolution (cohabitation).
--              Au calcul de paie, on applique à chaque jour le contrat en
--              vigueur à sa date (celui dont [date_debut, date_fin] couvre
--              la date du jour).
--              Colonnes structure / type_contrat / heures_hebdo /
--              matricule_silae / type_periode calées sur celles de `collaborateurs`. Le
--              matricule_silae peut changer avec la structure : il vit donc
--              ici, dans l'historique.
-- Pré-requis : `collaborateurs.collab_id` est PRIMARY KEY (vérifié) → la clé
--              étrangère est possible.
--
-- ⚠️ RLS ACTIVÉE (rowsecurity = true) — MAIS la policy "lecture
--    historique_contrats" (using (true)) OUVRE la lecture à `anon`. Donnée
--    sensible (contrats) : lecture ouverte de phase DEV, à RESÉCURISER avec
--    l'auth admin avant la mise en production (post-15/06).
--
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

create table public.historique_contrats (
  id              bigint generated always as identity primary key,
  collab_id       text   not null,
  date_debut      date   not null,
  date_fin        date,                       -- NULL = contrat en cours
  structure       text,
  type_contrat    text,
  heures_hebdo    numeric,
  matricule_silae text,
  created_at      timestamptz default now(),
  type_periode    text   check (type_periode in ('civil', 'decalee')),

  constraint historique_contrats_collab_id_fkey
    foreign key (collab_id)
    references public.collaborateurs (collab_id)
);

-- Accélère la résolution « contrat en vigueur à une date donnée »
-- (filtrage par collaborateur puis par date de début).
create index idx_historique_contrats_collab_date
  on public.historique_contrats (collab_id, date_debut);

-- -----------------------------------------------------------------------------
-- ACCÈS LECTURE (phase DEV) — exécuté en base le 2026-06-10.
-- RLS activée sur la table ; cette policy + ce grant ouvrent la lecture à la
-- clé `anon` pour que l'app admin (admin-v2.html) lise le contexte contractuel.
-- ⚠️ LECTURE OUVERTE (using (true)) — NON sécurisé. À RESÉCURISER avec l'auth
--    admin APRÈS le 15/06 : restreindre la policy au rôle admin authentifié et
--    retirer l'accès `anon`.
-- -----------------------------------------------------------------------------
grant select on public.historique_contrats to anon;

create policy "lecture historique_contrats"
  on public.historique_contrats
  for select
  to public
  using (true);
