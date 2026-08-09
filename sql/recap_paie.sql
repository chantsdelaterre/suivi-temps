-- =============================================================================
-- recap_paie.sql
-- Date       : 2026-06-07
-- Rôle       : Niveau 3 de l'architecture paie — SYNTHÈSE AGRÉGÉE. Une seule
--              ligne par collaborateur / période. Totaux RECOPIÉS depuis le
--              calcul de paie (séparés : heures travaillées / AT / CS, nombre
--              de CP, nombre de jours travaillés) + workflow (validation,
--              signature, note admin).
--
--              Source de vérité = `paie_detail` (détail jour par jour figé) +
--              `historique_contrats` (contexte contractuel à la date). Cette
--              table n'est qu'une AGRÉGATION figée pour consultation / export.
--
-- NE stocke PAS le contexte contractuel (structure, type_contrat, heures_hebdo,
--   matricule_silae…) : il vit dans `historique_contrats`.
--
-- ⚠️ `nb_at`, `nb_cs` et `date_fin_validation` ont été ajoutées EN BASE par ALTER
--    (nb_at/nb_cs non tracés ; date_fin_validation = lot 2, 2026-08-09). Elles sont
--    désormais INTÉGRÉES au CREATE TABLE ci-dessous pour que ce script recrée une
--    table fidèle à la base.
--
-- collab_id : clé étrangère vers `collaborateurs` (saisie manuelle, garde-fou).
-- Unicité   : (periode_id, collab_id) — une seule ligne de récap par collab et
--             par période.
--
-- ⚠️ RLS ACTIVÉE (rowsecurity = true) — MAIS des policies de phase DEV
--    (lecture + insertion + maj, using/with check (true)) OUVRENT l'accès à
--    `anon` (ouvert le 13/06, cf. section « ACCÈS » en fin de fichier). Donnée
--    TRÈS sensible (synthèse de paie) : à RESÉCURISER IMPÉRATIVEMENT avec l'auth
--    admin avant la mise en production (post-15/06).
--
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              ⚠️ Recrée la table : exécuter les 3 étapes DANS L'ORDRE et
--              S'ARRÊTER si l'étape 1 renvoie un count > 0 (table non vide).
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- ÉTAPE 1 — RAPPEL DE SÉCURITÉ : vérifier que la table est VIDE avant le drop.
--           Si le résultat est > 0, NE PAS continuer (ne pas exécuter l'étape 2).
-- -----------------------------------------------------------------------------
select count(*) from public.recap_paie;


-- -----------------------------------------------------------------------------
-- ÉTAPE 2 — SUPPRESSION de l'ancienne table (à lancer SEULEMENT si count = 0).
-- -----------------------------------------------------------------------------
drop table public.recap_paie;


-- -----------------------------------------------------------------------------
-- ÉTAPE 3 — CRÉATION de la nouvelle structure.
-- -----------------------------------------------------------------------------
create table public.recap_paie (
  -- Identité
  id                   bigint generated always as identity primary key,
  periode_id           text        not null,
  collab_id            text        not null,
  nom_affiche          text,

  -- Totaux recopiés depuis paie_detail (calcul de paie)
  heures_travaillees   numeric,
  heures_at            numeric,
  heures_cs            numeric,
  nb_at                integer     default 0,   -- nb de jours AT — ajoutée en base par ALTER (non tracé), intégrée au CREATE le 2026-08-09
  nb_cs                integer     default 0,   -- nb de jours CS — idem
  nb_cp                integer,
  nb_jours_travailles  integer,

  -- Workflow
  statut_validation    text,
  date_validation      text,
  date_fin_validation  date,                    -- lot 2 (2026-08-09) : borne de clôture partielle (NULL = validation normale ; date = validé jusqu'à cette date incluse)
  statut_signature     text,
  note_admin           text,

  created_at           timestamptz default now(),

  constraint recap_paie_collab_id_fkey
    foreign key (collab_id)
    references public.collaborateurs (collab_id),

  constraint recap_paie_unique
    unique (periode_id, collab_id)
);

-- -----------------------------------------------------------------------------
-- ACCÈS LECTURE / ÉCRITURE (phase DEV) — exécuté en base le 2026-06-13.
-- RLS activée ; ces grants + policies ouvrent SELECT/INSERT/UPDATE à `anon`
-- pour que l'app admin (admin-v2.html) écrive la validation/clôture (recap_paie).
-- ⚠️ LECTURE **ET ÉCRITURE** OUVERTES (using/with check (true)) — NON sécurisé,
--    synthèse de paie (très sensible). À RESÉCURISER IMPÉRATIVEMENT APRÈS le 15/06 :
--    restreindre au rôle admin authentifié et retirer l'accès `anon`.
-- -----------------------------------------------------------------------------
grant select, insert, update on public.recap_paie to anon;

create policy "lecture recap_paie"
  on public.recap_paie
  for select
  to public
  using (true);

create policy "insertion recap_paie"
  on public.recap_paie
  for insert
  to public
  with check (true);

create policy "maj recap_paie"
  on public.recap_paie
  for update
  to public
  using (true)
  with check (true);
