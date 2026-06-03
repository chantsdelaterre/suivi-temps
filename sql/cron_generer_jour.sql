-- =============================================================================
-- cron_generer_jour.sql
-- Date       : 2026-06-03
-- But        : Planifie l'appel quotidien de public.generer_jour_aujourdhui()
--              via pg_cron, pour générer automatiquement les « jours » chaque
--              matin (transposition du trigger journalier GAS).
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
--
-- Heure       : pg_cron s'exécute en UTC. Le job est planifié à 02:00 UTC :
--                 - 3h du matin à Paris en hiver (CET,  UTC+1)
--                 - 4h du matin à Paris en été   (CEST, UTC+2)
--              La dérive saisonnière de ±1h est sans conséquence (génération
--              nocturne, bien avant les saisies du matin), et la date est de
--              toute façon calculée en Europe/Paris dans la fonction.
-- =============================================================================

-- 1. Activer l'extension pg_cron (sans effet si déjà activée)
create extension if not exists pg_cron;

-- 2. Planifier l'appel quotidien de la fonction (02:00 UTC)
--    Relancer ce cron.schedule avec le même nom met à jour le job existant
--    (pas de doublon) -> rejouable sans risque.
select cron.schedule(
  'generer-jour-quotidien',
  '0 2 * * *',
  $$ select public.generer_jour_aujourdhui(); $$
);

-- =============================================================================
-- POUR MÉMOIRE — commandes d'exploitation (ne pas exécuter à l'installation)
-- =============================================================================
--
-- Lister les jobs planifiés :
--   select jobid, jobname, schedule, command, active from cron.job order by jobid;
--
-- Historique des exécutions (succès / échec) :
--   select jobid, runid, status, return_message, start_time, end_time
--   from cron.job_run_details order by start_time desc limit 20;
--
-- Désactiver temporairement le job (reste défini, ne tourne plus) :
--   update cron.job set active = false where jobname = 'generer-jour-quotidien';
--   -- réactiver : update cron.job set active = true where jobname = 'generer-jour-quotidien';
--
-- Supprimer définitivement le job :
--   select cron.unschedule('generer-jour-quotidien');
-- =============================================================================
