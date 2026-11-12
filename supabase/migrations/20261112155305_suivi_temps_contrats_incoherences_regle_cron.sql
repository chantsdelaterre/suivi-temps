-- Appliquée en base le 12/11/2026 (connecteur Supabase).
-- Le compteur d'incohérences de l'onglet Contrats suit désormais la règle de
-- synchroniser_activite() : un collaborateur entre deux contrats (contrat à venir)
-- n'est plus signalé, et on compte des personnes, plus des lignes de contrat.
create or replace function public.contrats_incoherences()
returns integer language sql stable security definer set search_path to 'public' as $$
  -- Personnes actives que synchroniser_activite() aurait dû désactiver.
  -- Même règle que le cron : aucun contrat sans fin, terminé depuis moins d'un jour, ou à venir.
  -- Compte des PERSONNES, pas des lignes. Non nul seulement si le cron n'a pas tourné.
  select count(*)::integer
  from collaborateurs c
  where coalesce(c.actif, false)
    and not exists (
      select 1 from historique_contrats h
      where h.collab_id = c.collab_id
        and (h.date_fin is null
             or h.date_fin >= (now() at time zone 'Europe/Paris')::date - 1
             or h.date_debut > (now() at time zone 'Europe/Paris')::date));
$$;
revoke execute on function public.contrats_incoherences() from public, anon, authenticated;
