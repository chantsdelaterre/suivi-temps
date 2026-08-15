-- =============================================================================
-- derniere_saisie_par_collab.sql
-- Date       : 2026-08-15
-- Rôle       : dernière date de SAISIE RÉELLE par collaborateur — alimente la
--              colonne « Dernière saisie » de l'onglet Récap (admin-v2.html,
--              chargerRecap). Renvoie (collab_id text, derniere_saisie date).
--
-- Pourquoi une RPC : chargerRecap rapatriait TOUTE la table `jours`
--              (~18 000 lignes/an) sans filtre ni pagination, pour n'en tirer
--              qu'UNE date par collab. PostgREST tronque à 1000 lignes
--              (~17 jours × 57 collabs) → ~9 collaborateurs sans saisie récente
--              affichaient « — » à tort. L'agrégation en base supprime la
--              troncature (renvoie ~50-60 lignes) et le calcul côté front.
--
-- ⚠️ Le critère « SAISI » vit DÉSORMAIS ICI, plus dans le front : un début de
--    créneau non vide, OU un type_jour dans CP/AT/CS. Toute évolution de ce
--    critère se fait EN BASE (dans cette fonction), jamais plus dans le front.
--
-- ⚠️ `coalesce(j.c*_debut, '') <> ''` est DÉLIBÉRÉ : il écarte la chaîne vide
--    EN PLUS du null, exactement comme le faisait le `!!(…)` du front. Un simple
--    `is not null` retiendrait des jours à créneau vide '' et CHANGERAIT la
--    « dernière saisie » de certains collaborateurs.
--
-- ⚠️ CREATE FUNCTION re-grante EXECUTE à `public` À CHAQUE création → le revoke
--    ci-dessous est OBLIGATOIRE après chaque `create or replace`.
--
-- Droits : `anon` a l'EXÉCUTION (contrairement à candidats_cloture_anticipee,
--          réservée à service_role) parce que c'est une lecture NON NOMINATIVE
--          — un identifiant et une date — appelée DIRECTEMENT par le front, sans
--          passer par une Edge Function.
--
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

create or replace function derniere_saisie_par_collab()
returns table (collab_id text, derniere_saisie date)
language sql
stable
as $$
  select j.collab_id, max(j.date_jour)
  from public.jours j
  where coalesce(j.c1_debut, '') <> ''
     or coalesce(j.c2_debut, '') <> ''
     or coalesce(j.c3_debut, '') <> ''
     or j.type_jour in ('CP','AT','CS')
  group by j.collab_id;
$$;

revoke execute on function derniere_saisie_par_collab() from public;
grant  execute on function derniere_saisie_par_collab() to anon;
