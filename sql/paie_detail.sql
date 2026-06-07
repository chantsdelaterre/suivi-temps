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
--      (type_jour_valide, heures_valide, ajuste_admin, note_admin).
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
-- ⚠️ RLS NON ACTIVÉE — donnée sensible (paie / contrats). RLS à activer
--    IMPÉRATIVEMENT avant la mise en production de l'écran admin
--    (comme `historique_contrats`).
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

  constraint paie_detail_collab_id_fkey
    foreign key (collab_id)
    references public.collaborateurs (collab_id),

  constraint paie_detail_unique
    unique (periode_id, collab_id, date_jour)
);

-- Retrouve vite toutes les lignes d'une paie (un collab sur une période).
create index idx_paie_detail_periode_collab
  on public.paie_detail (periode_id, collab_id);
