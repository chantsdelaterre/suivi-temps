-- =============================================================================
-- trigger_quotidien.sql
-- Date       : 2026-06-04
-- But        : « Chef d'orchestre » du trigger quotidien — équivalent du
--              triggerJournalier() GAS. Enchaîne les 4 fonctions automatiques
--              dans l'ordre, chacune isolée, et renvoie un rapport texte.
--
-- Ordre des 4 étapes :
--   1. activer_collabs_en_attente()    -- collabs 'en_attente' dont la date est venue -> 'actif'
--   2. ouvrir_geler_periodes()         -- planifiee->ouverte (date_debut), ouverte->gelee (lendemain date_fin)
--   3. generer_periodes_suivantes()    -- maintient 2 périodes 'planifiee' d'avance par type
--   4. generer_jour_aujourdhui()       -- crée le jour du jour pour chaque collab actif d'une période ouverte
--
-- Gestion d'erreur : ISOLÉE par étape (BEGIN/EXCEPTION WHEN OTHERS), comme les
--              try/catch du GAS. Une étape qui échoue est notée dans le rapport
--              (ses écritures sont annulées au savepoint) et N'EMPÊCHE PAS les
--              étapes suivantes. Le SELECT réussit donc toujours : c'est le
--              rapport qui signale les erreurs.
-- Retour     : un TEXTE-RAPPORT multi-lignes, destiné à être envoyé par mail
--              plus tard via une Edge Function (PAS d'envoi de mail ici).
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Cron        : appelée chaque jour par le job pg_cron 'trigger-quotidien'
--              (voir sql/cron_trigger_quotidien.sql).
-- =============================================================================

create or replace function public.trigger_quotidien()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := (now() at time zone 'Europe/Paris')::date;
  v_rapport text := 'Trigger quotidien — ' || to_char(v_today, 'DD/MM/YYYY') || E'\n';
  v_n       integer;
  v_txt     text;
begin
  -- 1. Activation des collaborateurs en attente
  begin
    v_n := public.activer_collabs_en_attente();
    v_rapport := v_rapport || 'Activation        : ' || v_n || ' collab(s) activé(s)' || E'\n';
  exception when others then
    v_rapport := v_rapport || 'Activation        : ERREUR - ' || sqlerrm || E'\n';
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
$$;
