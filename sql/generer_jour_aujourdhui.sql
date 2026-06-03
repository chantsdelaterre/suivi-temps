-- =============================================================================
-- generer_jour_aujourdhui.sql
-- Date       : 2026-06-03
-- But        : Génère le « jour » du jour pour chaque collaborateur actif
--              rattaché à une période de paie ouverte (de même type_periode).
--              Transposition de la logique GAS genererJourAujourdhui() vers
--              Supabase / PostgreSQL.
--              - date_jour & jour_semaine calculés en heure d'Europe/Paris
--              - type_jour par défaut = 'travaillée'
--              - anti-doublon via la clé primaire jour_id (ON CONFLICT DO NOTHING)
--              - idempotente : peut être relancée sans créer de doublon
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

create or replace function public.generer_jour_aujourdhui()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date     date := (now() at time zone 'Europe/Paris')::date;
  v_jour_sem text := (array['Dimanche','Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi'])
                       [ extract(dow from (now() at time zone 'Europe/Paris')::date)::int + 1 ];
  v_inserted integer;
begin
  insert into public.jours (jour_id, collab_id, date_jour, jour_semaine, periode_id, type_jour)
  select
    c.collab_id || '_' || to_char(v_date, 'YYYY-MM-DD'),  -- jour_id
    c.collab_id,                                          -- collab_id
    v_date,                                               -- date_jour (type date)
    v_jour_sem,                                           -- jour_semaine ('Lundi', ...)
    p.periode_id,                                         -- periode_id
    'travaillée'                                          -- type_jour
  from public.periodes p
  join public.collaborateurs c
       on c.type_periode = p.type_periode
      and c.actif = true
  where p.statut = 'ouverte'
  on conflict (jour_id) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;
