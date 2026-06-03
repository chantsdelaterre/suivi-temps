-- =============================================================================
-- activer_collabs_en_attente.sql
-- Date       : 2026-06-03
-- But        : Active les collaborateurs « en attente » dont la date
--              d'activation est arrivée. Transposition de la logique GAS
--              activerCollabsEnAttente() vers Supabase / PostgreSQL.
--              Règle : pour chaque collab avec statut = 'en_attente'
--              ET date_activation non NULL ET date_activation <= aujourd'hui
--              (heure d'Europe/Paris) → statut = 'actif' ET actif = true.
--              Ne touche ni les 'inactif' ni les 'actif'.
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Cron        : PAS branchée seule sur pg_cron. Elle sera appelée par le futur
--              « chef d'orchestre » quotidien (équivalent du triggerJournalier
--              GAS, qui enchaîne activation → clôture/ouverture → génération).
-- =============================================================================

create or replace function public.activer_collabs_en_attente()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := (now() at time zone 'Europe/Paris')::date;
  v_updated integer;
begin
  update public.collaborateurs
  set statut = 'actif',
      actif  = true
  where statut = 'en_attente'
    and date_activation is not null
    and date_activation <= v_today;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;
