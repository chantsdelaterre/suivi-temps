-- =============================================================================
-- ouvrir_geler_periodes.sql
-- Date       : 2026-06-03
-- But        : Transitions AUTOMATIQUES des périodes de paie :
--                - 'planifiee' -> 'ouverte'  quand date_debut <= aujourd'hui
--                - 'ouverte'   -> 'gelee'    quand date_fin   <  aujourd'hui
--                  (gel le LENDEMAIN de date_fin)
--              Dates calculées en heure d'Europe/Paris (pas UTC).
--              Ordre ouvrir-puis-geler volontaire : une période très en retard
--              (date_fin déjà passée) passe planifiee -> ouverte -> gelee en un
--              seul appel.
-- NON inclus  : la transition 'gelee' -> 'cloturee' n'est PAS ici. La clôture
--              est une ACTION ADMIN (validation de paie), pas automatique.
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Cron        : PAS branchée seule sur pg_cron. Elle sera appelée par le futur
--              « chef d'orchestre » quotidien (équivalent du triggerJournalier
--              GAS, qui enchaîne activation → ouverture/gel → génération).
-- =============================================================================

create or replace function public.ouvrir_geler_periodes()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today    date := (now() at time zone 'Europe/Paris')::date;
  v_ouvertes integer;
  v_gelees   integer;
begin
  -- 1) planifiee dont la date de début est atteinte -> ouverte
  update public.periodes
  set statut = 'ouverte'
  where statut = 'planifiee'
    and date_debut is not null
    and date_debut <= v_today;
  get diagnostics v_ouvertes = row_count;

  -- 2) ouverte dont la date de fin est strictement passée -> gelee
  --    (gel le lendemain de date_fin : on gèle quand date_fin < aujourd'hui)
  update public.periodes
  set statut = 'gelee'
  where statut = 'ouverte'
    and date_fin is not null
    and date_fin < v_today;
  get diagnostics v_gelees = row_count;

  return v_ouvertes || ' ouverte(s), ' || v_gelees || ' gelée(s)';
end;
$$;
