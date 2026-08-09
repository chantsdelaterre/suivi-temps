-- =============================================================================
-- paie_detail.sql
-- Date       : 2026-06-07
-- Rôle       : Niveau 2 de l'architecture paie — PHOTO FIGÉE jour par jour des
--              jours d'une période, prise à la CLÔTURE (après validation et
--              ajustements admin). Une ligne par collaborateur / jour.
--              Support du RELEVÉ DÉTAILLÉ signé.
--
-- Deux couches :
--   1. SAISIE COLLAB FIGÉE — recopie de `jours` au moment de la clôture
--      (type_jour, créneaux, totaux, commentaire, nb_modifications…).
--   2. VALIDATION ADMIN — valeurs finales retenues pour la paie + traçabilité
--      (type_jour_valide, heures_valide, ajuste_admin, note_admin,
--       date_ajuste_admin [ajoutée 13/06 ; écrite par l'Edge `ajuster-paie`
--       depuis le 09/08/2026 — jamais par le front, valeur posée côté serveur.
--       Les ajustements ANTÉRIEURS au 09/08 restent NULL et ne sont pas
--       reconstituables → « Modif admin » sans date à l'écran (113 lignes)]).
--
-- NE stocke PAS le contexte contractuel (structure, heures_hebdo, type_contrat,
--   matricule_silae…) : on le retrouve via `historique_contrats` (contrat en
--   vigueur à la date du jour).
--
-- periode_id : PAS de clé étrangère — créé par le système (génération), fiable.
-- collab_id  : clé étrangère vers `collaborateurs` — table à saisie MANUELLE,
--              garde-fou utile.
--
-- Unicité    : (periode_id, collab_id, date_jour) — empêche qu'un même jour
--              d'un même collab dans une même période soit figé en double
--              (protection contre une double clôture).
--
-- ⚠️ RLS ACTIVÉE (rowsecurity = true) — MAIS des policies de phase DEV
--    (lecture + insertion + maj, using/with check (true)) OUVRENT l'accès à
--    `anon`. Donnée TRÈS sensible (ÉCRITURE sur des données de paie) : à
--    RESÉCURISER IMPÉRATIVEMENT avec l'auth admin avant la mise en production
--    (post-15/06) — cf. section « ACCÈS LECTURE/ÉCRITURE » en fin de fichier.
--
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

create table public.paie_detail (
  -- Identité / figement
  id                  bigint generated always as identity primary key,
  periode_id          text        not null,   -- pas de FK : créé par le système
  collab_id           text        not null,
  date_jour           date        not null,
  jour_semaine        text,
  date_cloture        timestamptz default now(),

  -- Couche 1 — saisie collab figée (photo de `jours`)
  type_jour           text,
  c1_debut            text,
  c1_fin              text,
  c2_debut            text,
  c2_fin              text,
  c3_debut            text,
  c3_fin              text,
  total_heures        numeric,
  commentaire         text,
  remarque_manager    text,
  total_hebdo_prog    numeric,
  nb_modifications    integer,
  date_derniere_modif text,

  -- Couche 2 — validation admin
  type_jour_valide    text,                   -- type retenu en paie (peut devenir CS)
  heures_valide       numeric,                -- heures finales validées pour la paie
  ajuste_admin        boolean     default false,  -- jour modifié par l'admin ?
  note_admin          text,
  date_ajuste_admin   timestamptz,                -- ajoutée le 13/06 (ALTER) ; écrite par l'Edge `ajuster-paie` depuis le 09/08/2026 (jamais par le front). Ajustements antérieurs = NULL, non reconstituables

  constraint paie_detail_collab_id_fkey
    foreign key (collab_id)
    references public.collaborateurs (collab_id),

  constraint paie_detail_unique
    unique (periode_id, collab_id, date_jour)
);

-- Retrouve vite toutes les lignes d'une paie (un collab sur une période).
create index idx_paie_detail_periode_collab
  on public.paie_detail (periode_id, collab_id);

-- -----------------------------------------------------------------------------
-- ACCÈS LECTURE / ÉCRITURE (phase DEV) — exécuté en base le 2026-06-10.
-- RLS activée ; ces grants + policies ouvrent SELECT/INSERT/UPDATE à `anon`
-- pour que l'app admin (admin-v2.html) puisse importer/figer la paie en dev.
-- ⚠️ LECTURE **ET ÉCRITURE** OUVERTES (using/with check (true)) — NON sécurisé,
--    et PLUS sensible que historique_contrats (écriture sur des données de paie).
--    À RESÉCURISER IMPÉRATIVEMENT APRÈS le 15/06 : restreindre au rôle admin
--    authentifié et retirer l'accès `anon`.
-- -----------------------------------------------------------------------------
grant select, insert, update on public.paie_detail to anon;

create policy "lecture paie_detail"
  on public.paie_detail
  for select
  to public
  using (true);

create policy "insertion paie_detail"
  on public.paie_detail
  for insert
  to public
  with check (true);

create policy "maj paie_detail"
  on public.paie_detail
  for update
  to public
  using (true)
  with check (true);
