-- =============================================================================
-- synchroniser_activite.sql
-- Date       : 2026-09-14 (créée) · 2026-09-28 (ajout tâche « envoyer lien »)
-- But        : Synchronise actif/statut des collaborateurs d'après les contrats
--              (historique_contrats). Actif s'il existe un contrat couvrant
--              aujourd'hui ; désactivé sinon (tolérance J-1 sur date_fin,
--              exclusion des contrats à venir). Renvoie « N activé(s), M
--              désactivé(s), P tâche(s) lien ». Appelée par trigger_quotidien()
--              (étape 1) ET par les Edge ajouter-contrat / creer-collab
--              (démarrage le jour même, idempotent).
--
-- Ajout du 28/09/2026 — TÂCHE « Envoyer le lien de l'appli » :
--   À chaque TRANSITION inactif->actif (l'UPDATE d'activation ne matche que
--   actif=false), on crée une tâche journal_taches marquée mouvement='activation',
--   tiers='EMPLOYE', statut='a_faire'. Garde-fou d'idempotence : on ne crée PAS si
--   une tâche 'activation' est DÉJÀ à faire pour ce collab (évite les doublons ;
--   permet de re-créer après une réactivation si l'ancienne a été 'faite').
--   Prérequis : le CHECK journal_taches_mouvement_chk doit autoriser 'activation'.
--   Réalisé via une CTE modifiante (UPDATE ... RETURNING -> INSERT ... WHERE NOT EXISTS)
--   pour capturer les collabs réellement activés dans la même requête.
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Droits      : service_role uniquement. ⚠️ Sans le GRANT ci-dessous, l'appel
--              depuis les Edge échoue en « permission denied » — constaté le
--              14/09/2026.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.synchroniser_activite()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_actives integer;
  v_inactives integer;
  v_taches integer;
begin
  -- ACTIVATION + création gardée de la tâche « Envoyer le lien de l'appli »
  -- (une seule requête : UPDATE des activés -> INSERT des tâches manquantes).
  with activ as (
    update collaborateurs c
    set actif = true, statut = 'actif'
    where coalesce(c.actif, false) = false
      and exists (
        select 1 from historique_contrats h
        where h.collab_id = c.collab_id
          and h.date_debut <= v_today
          and (h.date_fin is null or h.date_fin >= v_today)
      )
    returning c.collab_id
  ),
  ins as (
    insert into journal_taches (collab_id, mouvement, objet, tiers, statut)
    select a.collab_id, 'activation', 'Envoyer le lien de l''appli', 'EMPLOYE', 'a_faire'
    from activ a
    where not exists (               -- garde-fou : pas de doublon si une tâche est déjà À FAIRE
      select 1 from journal_taches t
      where t.collab_id = a.collab_id
        and t.mouvement = 'activation'
        and t.statut = 'a_faire'
    )
    returning 1
  )
  select (select count(*) from activ), (select count(*) from ins)
  into v_actives, v_taches;

  -- DÉSACTIVATION
  update collaborateurs c
  set actif = false, statut = 'inactif'
  where coalesce(c.actif, false) = true
    and not exists (
      select 1 from historique_contrats h
      where h.collab_id = c.collab_id
        and (
          h.date_fin is null
          or h.date_fin >= v_today - 1
          or h.date_debut > v_today
        )
    );
  get diagnostics v_inactives = row_count;

  return v_actives || ' activé(s), ' || v_inactives || ' désactivé(s), '
      || v_taches || ' tâche(s) lien';
end;
$function$
;

revoke execute on function public.synchroniser_activite() from public;
grant execute on function public.synchroniser_activite() to service_role;
