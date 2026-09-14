-- =============================================================================
-- synchroniser_activite.sql
-- Date       : 2026-09-14
-- But        : Synchronise actif/statut des collaborateurs d'après les contrats
--              (historique_contrats). Actif s'il existe un contrat couvrant
--              aujourd'hui ; désactivé sinon (tolérance J-1 sur date_fin,
--              exclusion des contrats à venir). Renvoie « N activé(s), M
--              désactivé(s) ». Appelée par trigger_quotidien() (étape 1) ET par
--              les Edge ajouter-contrat / creer-collab (démarrage le jour même,
--              idempotent).
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
begin
  update collaborateurs c
  set actif = true, statut = 'actif'
  where coalesce(c.actif, false) = false
    and exists (
      select 1 from historique_contrats h
      where h.collab_id = c.collab_id
        and h.date_debut <= v_today
        and (h.date_fin is null or h.date_fin >= v_today)
    );
  get diagnostics v_actives = row_count;

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

  return v_actives || ' activé(s), ' || v_inactives || ' désactivé(s)';
end;
$function$
;

revoke execute on function public.synchroniser_activite() from public;
grant execute on function public.synchroniser_activite() to service_role;
