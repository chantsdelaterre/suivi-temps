-- =============================================================================
-- trigger_quotidien.sql
-- Date       : 2026-09-14  (remplace la version du 2026-06-04 qui appelait encore
--              activer_collabs_en_attente en étape 1)
-- But        : « Chef d'orchestre » du trigger quotidien. Enchaîne les 4
--              fonctions automatiques dans l'ordre, chacune isolée, et renvoie un
--              rapport texte.
--
-- Ordre des 4 étapes :
--   1. synchroniser_activite()       -- actif/statut d'après les contrats (historique_contrats)
--   2. ouvrir_geler_periodes()       -- planifiee->ouverte (date_debut), ouverte->gelee (lendemain date_fin)
--   3. generer_periodes_suivantes()  -- maintient 2 périodes 'planifiee' d'avance par type
--   4. generer_jour_aujourdhui()     -- crée le jour du jour pour chaque collab actif d'une période ouverte
--
-- Gestion d'erreur : ISOLÉE par étape (BEGIN/EXCEPTION WHEN OTHERS). Une étape qui
--              échoue est notée dans le rapport et N'EMPÊCHE PAS les suivantes.
-- Retour     : un TEXTE-RAPPORT multi-lignes.
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Droits      : postgres uniquement (cf. table des droits en base).
-- Cron        : appelée chaque jour par le job pg_cron 'trigger-quotidien'
--              (voir sql/cron_trigger_quotidien.sql).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trigger_quotidien()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  declare
    v_today   date := (now() at time zone 'Europe/Paris')::date;
    v_rapport text := 'Trigger quotidien — ' || to_char(v_today, 'DD/MM/YYYY') || E'\n';
    v_n       integer;
    v_txt     text;
  begin
    -- 1. Synchronisation de l'activité selon les contrats
    begin
      v_txt := public.synchroniser_activite();
      v_rapport := v_rapport || 'Activite          : ' || v_txt || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Activite          : ERREUR - ' || sqlerrm || E'\n';
    end;
    -- 2. Ouverture / gel automatique des périodes
    begin
      v_txt := public.ouvrir_geler_periodes();
      v_rapport := v_rapport || 'Périodes ouv/gel  : ' || v_txt || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Périodes ouv/gel  : ERREUR - ' || sqlerrm || E'\n';
    end;
    -- 3. Génération des périodes suivantes (2 d'avance par type)
    begin
      v_txt := public.generer_periodes_suivantes();
      v_rapport := v_rapport || 'Génération périodes: ' || v_txt || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Génération périodes: ERREUR - ' || sqlerrm || E'\n';
    end;
    -- 4. Génération du jour du jour
    begin
      v_n := public.generer_jour_aujourdhui();
      v_rapport := v_rapport || 'Jours générés     : ' || v_n || ' créé(s)' || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Jours générés     : ERREUR - ' || sqlerrm || E'\n';
    end;
    return v_rapport;
  end;
  $function$
;
