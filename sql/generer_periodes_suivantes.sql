-- =============================================================================
-- generer_periodes_suivantes.sql
-- Date       : 2026-06-03
-- But        : Génération automatique des périodes de paie, méthode
--              « 2 périodes planifiee d'avance par type » (civil ET decalee).
--              Si un type a moins de 2 périodes 'planifiee', en générer juste
--              assez pour revenir à 2.
--
-- Règles de calcul (cf. CLAUDE.md, section "Règle de génération des périodes")
--   - CIVILES  : un mois calendaire. date_debut = 1er du mois,
--                date_fin = dernier jour du mois. Nommage par le mois (début=fin).
--   - DECALEES : date_fin = 1er dimanche >= 15 du mois cible ;
--                date_debut = lendemain de la date_fin de la période précédente
--                (jointif, un lundi). NOMMAGE PAR LE MOIS DE DATE_FIN
--                (corrige la collision DEC_2026_06 du nommage par date_debut).
--   - Point de départ : date_fin la plus lointaine des périodes du type,
--                statut 'planifiee' OU 'ouverte' (repli si aucune référence).
--   - Dates calculées en Europe/Paris. Nouvelles périodes au statut 'planifiee'.
--   - date_cloture ABANDONNÉE (non renseignée).
--
-- Nommage    : periode_id = CIV_aaaa_mm / DEC_aaaa_mm
--              nom_periode = CIVIL_aaaa_mm / DECAL_aaaa_mm
--              (civiles : mm = mois ; décalées : mm = mois de date_fin)
--
-- Collisions : ON CONFLICT (periode_id) DO NOTHING — NON silencieux :
--              compteurs attendu/créé par type rapportés dans le texte de retour
--              (ex. "decalees: 1/2 créées — ⚠️ collision(s)…") + RAISE WARNING
--              nommant le periode_id ignoré. La fonction ne s'interrompt pas
--              (robuste pour un run quotidien, rejouable).
--
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Cron        : PAS branchée seule sur pg_cron. Elle sera appelée par le futur
--              « chef d'orchestre » quotidien (équivalent du triggerJournalier GAS).
-- =============================================================================

create or replace function public.generer_periodes_suivantes()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today        date := (now() at time zone 'Europe/Paris')::date;
  v_nb_civil     integer;
  v_nb_decalee   integer;
  v_att_civil    integer := 0;   -- attendues (à créer)
  v_att_decalee  integer := 0;
  v_cree_civil   integer := 0;   -- réellement créées
  v_cree_decalee integer := 0;
  v_ref          date;
  v_debut        date;
  v_fin          date;
  v_id           text;
  v_nom          text;
  v_ins          integer;
  i              integer;
begin
  ---------------------------------------------------------------------------
  -- CIVILES : un mois calendaire (1er -> dernier jour). Nommage INCHANGÉ.
  ---------------------------------------------------------------------------
  select count(*) into v_nb_civil
  from public.periodes where type_periode = 'civil' and statut = 'planifiee';
  v_att_civil := greatest(0, 2 - v_nb_civil);

  if v_att_civil > 0 then
    select max(date_fin) into v_ref
    from public.periodes
    where type_periode = 'civil' and statut in ('planifiee','ouverte');
    if v_ref is null then
      v_ref := (date_trunc('month', v_today) - interval '1 day')::date;  -- repli : fin du mois précédent
    end if;

    for i in 1 .. v_att_civil loop
      v_debut := (date_trunc('month', v_ref) + interval '1 month')::date;
      v_fin   := (date_trunc('month', v_debut) + interval '1 month' - interval '1 day')::date;
      -- civile : debut et fin dans le MÊME mois -> nommer par date_debut == par date_fin
      v_id    := 'CIV_'   || to_char(v_debut,'YYYY') || '_' || to_char(v_debut,'MM');
      v_nom   := 'CIVIL_' || to_char(v_debut,'YYYY') || '_' || to_char(v_debut,'MM');

      insert into public.periodes (periode_id, nom_periode, type_periode, date_debut, date_fin, statut)
      values (v_id, v_nom, 'civil', v_debut, v_fin, 'planifiee')
      on conflict (periode_id) do nothing;
      get diagnostics v_ins = row_count;
      v_cree_civil := v_cree_civil + v_ins;
      if v_ins = 0 then
        raise warning 'generer_periodes_suivantes: civile % NON créée (periode_id déjà présent)', v_id;
      end if;

      v_ref := v_fin;
    end loop;
  end if;

  ---------------------------------------------------------------------------
  -- DECALEES : fin = 1er dimanche >= 15 ; debut = lendemain de la fin précédente.
  -- Nommage par le mois de DATE_FIN (corrige la collision).
  ---------------------------------------------------------------------------
  select count(*) into v_nb_decalee
  from public.periodes where type_periode = 'decalee' and statut = 'planifiee';
  v_att_decalee := greatest(0, 2 - v_nb_decalee);

  if v_att_decalee > 0 then
    select max(date_fin) into v_ref
    from public.periodes
    where type_periode = 'decalee' and statut in ('planifiee','ouverte');
    if v_ref is null then
      v_ref := (date_trunc('month', v_today)::date + 14);
      v_ref := v_ref + ((7 - extract(dow from v_ref)::int) % 7);  -- 1er dimanche >= 15 du mois courant
    end if;

    for i in 1 .. v_att_decalee loop
      v_debut := v_ref + 1;                                                   -- lendemain (lundi)
      v_fin   := (date_trunc('month', v_ref) + interval '1 month')::date + 14; -- le 15 du mois cible
      v_fin   := v_fin + ((7 - extract(dow from v_fin)::int) % 7);            -- 1er dimanche >= 15
      -- nommage par DATE_FIN
      v_id    := 'DEC_'   || to_char(v_fin,'YYYY') || '_' || to_char(v_fin,'MM');
      v_nom   := 'DECAL_' || to_char(v_fin,'YYYY') || '_' || to_char(v_fin,'MM');

      insert into public.periodes (periode_id, nom_periode, type_periode, date_debut, date_fin, statut)
      values (v_id, v_nom, 'decalee', v_debut, v_fin, 'planifiee')
      on conflict (periode_id) do nothing;
      get diagnostics v_ins = row_count;
      v_cree_decalee := v_cree_decalee + v_ins;
      if v_ins = 0 then
        raise warning 'generer_periodes_suivantes: decalee % NON créée (periode_id déjà présent)', v_id;
      end if;

      v_ref := v_fin;
    end loop;
  end if;

  return format('civiles: %s/%s créées, decalees: %s/%s créées%s',
                v_cree_civil, v_att_civil, v_cree_decalee, v_att_decalee,
                case when v_cree_civil < v_att_civil or v_cree_decalee < v_att_decalee
                     then ' — ⚠️ collision(s) : des périodes attendues n''ont pas été créées (voir warnings)'
                     else '' end);
end;
$$;
