-- =============================================================================
-- cron_trigger_quotidien.sql
-- Date       : 2026-06-04
-- But        : Planifie l'appel quotidien du chef d'orchestre
--              public.trigger_quotidien() via pg_cron.
--              REMPLACE l'ancien job 'generer-jour-quotidien' (qui n'appelait
--              que generer_jour_aujourdhui()). Désormais un seul job fait tout :
--              activation, ouverture/gel des périodes, génération des périodes
--              ET des jours.
--
-- Heure       : pg_cron s'exécute en UTC. Job planifié à 02:00 UTC :
--                 - 3h du matin à Paris en hiver (CET,  UTC+1)
--                 - 4h du matin à Paris en été   (CEST, UTC+2)
--              Dérive saisonnière de ±1h sans conséquence (exécution nocturne) ;
--              les dates sont de toute façon calculées en Europe/Paris dans les
--              fonctions.
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

-- Activer l'extension pg_cron (sans effet si déjà activée)
create extension if not exists pg_cron;

-- Bascule atomique : créer le nouveau job AVANT de supprimer l'ancien
-- (jamais sans cron actif, jamais de doublon).
begin;
  -- Nouveau job : appelle le chef d'orchestre tous les jours à 02:00 UTC
  select cron.schedule(
    'trigger-quotidien',
    '0 2 * * *',
    $$ select public.trigger_quotidien(); $$
  );

  -- Supprimer l'ancien job (n'appelait que la génération des jours)
  select cron.unschedule('generer-jour-quotidien');
commit;

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
--   update cron.job set active = false where jobname = 'trigger-quotidien';
--   -- réactiver : update cron.job set active = true where jobname = 'trigger-quotidien';
--
-- Supprimer définitivement le job :
--   select cron.unschedule('trigger-quotidien');
-- =============================================================================
