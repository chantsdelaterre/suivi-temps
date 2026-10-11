--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: activer_collabs_en_attente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.activer_collabs_en_attente() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: ajouter_contrat(text, date, text, text, text, numeric, text, date, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ajouter_contrat(p_collab_id text, p_date_debut date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_date_fin date DEFAULT NULL::date, p_taux_horaire numeric DEFAULT NULL::numeric) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_ouvert bigint;
  v_derniere_fin date;
begin
  select id into v_ouvert
  from historique_contrats
  where collab_id = p_collab_id and date_fin is null
  limit 1;
  if v_ouvert is not null then
    raise exception 'Ce collaborateur a deja un contrat ouvert. Cloturez-le avant d en ouvrir un nouveau.';
  end if;

  select max(date_fin) into v_derniere_fin
  from historique_contrats
  where collab_id = p_collab_id;
  if v_derniere_fin is not null and p_date_debut <= v_derniere_fin then
    raise exception 'La date de debut % doit etre posterieure a la fin du contrat precedent %', p_date_debut, v_derniere_fin;
  end if;

  if p_date_fin is not null and p_date_fin < p_date_debut then
    raise exception 'Date de fin % anterieure au debut % du contrat', p_date_fin, p_date_debut;
  end if;

  insert into historique_contrats (collab_id, date_debut, date_fin, structure, type_contrat, type_periode, heures_hebdo, matricule_silae, taux_horaire)
  values (p_collab_id, p_date_debut, p_date_fin, p_structure, p_type_contrat, p_type_periode, p_heures_hebdo, p_matricule_silae, p_taux_horaire);

  perform rafraichir_fiche_collab(p_collab_id);
  return p_collab_id;
end;
$$;


--
-- Name: candidats_cloture_anticipee(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.candidats_cloture_anticipee() RETURNS TABLE(collab_id text, nom_affiche text, structure text, date_fin_contrat date, periode_id text, nom_periode text, periode_date_debut date, periode_date_fin date)
    LANGUAGE sql STABLE
    AS $$
  with dernier_contrat as (
    select distinct on (hc.collab_id)
           hc.collab_id,
           hc.date_fin,
           hc.structure,
           hc.type_periode
    from historique_contrats hc
    order by hc.collab_id, hc.date_debut desc, hc.date_fin desc
  )
  select c.collab_id,
         c.nom_affiche,
         coalesce(dc.structure, c.structure),
         dc.date_fin,
         p.periode_id,
         p.nom_periode,
         p.date_debut,
         p.date_fin
  from dernier_contrat dc
  join collaborateurs c
    on c.collab_id = dc.collab_id
  join periodes p
    on p.statut = 'ouverte'
   and p.type_periode = coalesce(dc.type_periode, c.type_periode)
   and dc.date_fin between p.date_debut and p.date_fin
  where dc.date_fin is not null
    and dc.date_fin < current_date
    and not exists (
      select 1 from recap_paie rp
      where rp.periode_id = p.periode_id
        and rp.collab_id  = dc.collab_id
        and rp.date_fin_validation is not null
    )
  order by coalesce(dc.structure, c.structure), c.nom_affiche;
$$;


--
-- Name: cloturer_contrat(text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cloturer_contrat(p_collab_id text, p_date_fin date) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_id bigint;
  v_date_debut date;
begin
  select id, date_debut into v_id, v_date_debut
  from historique_contrats
  where collab_id = p_collab_id and date_fin is null
  limit 1;
  if v_id is null then
    raise exception 'Aucun contrat ouvert a cloturer pour %', p_collab_id;
  end if;
  if p_date_fin < v_date_debut then
    raise exception 'Date de fin % anterieure au debut du contrat %', p_date_fin, v_date_debut;
  end if;

  update historique_contrats set date_fin = p_date_fin where id = v_id;

  -- leve l'asymetrie : apres cloture, la fiche reflete l'etat courant reel
  -- (contrat encore courant -> recopie ; trou -> fiche inchangee + signalee)
  perform rafraichir_fiche_collab(p_collab_id);

  return p_collab_id;
end;
$$;


--
-- Name: collab_session(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.collab_session(p_token text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  c record;
  v_manager_token text;
  v_date_fin date;
begin
  select collab_id, prenom, nom, nom_affiche, structure,
         type_periode, equipe_id, role
    into c
  from collaborateurs
  where token = p_token and actif = true;

  if c.collab_id is null then
    return jsonb_build_object('ok', false, 'error', 'lien_invalide');
  end if;

  if c.role = 'responsable' and c.equipe_id is not null then
    select manager_token into v_manager_token
    from equipes where equipe_id = c.equipe_id;
  end if;

  -- Date de fin du dernier contrat terminé, s'il n'y a plus rien en cours
  select max(h.date_fin) into v_date_fin
  from historique_contrats h
  where h.collab_id = c.collab_id
    and h.date_fin is not null
    and h.date_fin < current_date
    and not exists (
      select 1 from historique_contrats a
      where a.collab_id = c.collab_id
        and a.date_debut <= current_date
        and (a.date_fin is null or a.date_fin >= current_date)
    );

  return jsonb_build_object('ok', true, 'collab', jsonb_build_object(
    'collab_id', c.collab_id,
    'prenom', c.prenom,
    'nom', c.nom,
    'nom_affiche', c.nom_affiche,
    'structure', c.structure,
    'type_periode', c.type_periode,
    'equipe_id', c.equipe_id,
    'role', c.role,
    'manager_token', v_manager_token,
    'contrat_termine_le', v_date_fin));
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: collaborateurs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collaborateurs (
    collab_id text NOT NULL,
    prenom text NOT NULL,
    nom text NOT NULL,
    nom_affiche text,
    email text,
    structure text,
    equipe_id text,
    type_contrat text,
    type_periode text,
    heures_hebdo numeric,
    statut text DEFAULT 'en_attente'::text,
    date_activation date,
    actif boolean DEFAULT false,
    role text DEFAULT 'collab'::text,
    employeur text,
    matricule_silae text,
    token text,
    created_at timestamp with time zone DEFAULT now(),
    telephone text,
    urgence_prenom text,
    urgence_nom text,
    urgence_telephone text,
    urgence_lien text,
    numero_securite_sociale text,
    CONSTRAINT collaborateurs_nss_cle_chk CHECK (((numero_securite_sociale IS NULL) OR ((97 - ((SUBSTRING(numero_securite_sociale FROM 1 FOR 13))::bigint % (97)::bigint)) = (SUBSTRING(numero_securite_sociale FROM 14 FOR 2))::integer))),
    CONSTRAINT collaborateurs_nss_format_chk CHECK (((numero_securite_sociale IS NULL) OR (numero_securite_sociale ~ '^[0-9]{15}$'::text)))
);


--
-- Name: COLUMN collaborateurs.numero_securite_sociale; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.collaborateurs.numero_securite_sociale IS 'Donnée sensible (RGPD) : identification directe. Lecture réservée à service_role, jamais anon.';


--
-- Name: collaborateurs_liste(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.collaborateurs_liste() RETURNS SETOF public.collaborateurs
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select * from collaborateurs
  order by nom_affiche;
$$;


--
-- Name: compteurs_paie_periodes(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compteurs_paie_periodes(p_periode_ids text[]) RETURNS TABLE(periode_id text, x integer, y integer)
    LANGUAGE sql STABLE
    AS $$
  with ids as (
    select unnest(p_periode_ids) as periode_id
  ),
  y_counts as (
    select pd.periode_id, count(distinct pd.collab_id) as n
    from paie_detail pd
    where pd.periode_id = any(p_periode_ids)
    group by pd.periode_id
  ),
  x_counts as (
    select rp.periode_id, count(distinct rp.collab_id) as n
    from recap_paie rp
    where rp.periode_id = any(p_periode_ids)
      and rp.statut_validation = 'valide'
    group by rp.periode_id
  )
  select i.periode_id,
         coalesce(x.n, 0)::integer,
         coalesce(y.n, 0)::integer
  from ids i
  left join x_counts x on x.periode_id = i.periode_id
  left join y_counts y on y.periode_id = i.periode_id;
$$;


--
-- Name: historique_contrats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.historique_contrats (
    id bigint NOT NULL,
    collab_id text NOT NULL,
    date_debut date NOT NULL,
    date_fin date,
    structure text,
    type_contrat text,
    heures_hebdo numeric,
    matricule_silae text,
    created_at timestamp with time zone DEFAULT now(),
    type_periode text,
    modifie_le timestamp with time zone,
    modifie_par text,
    taux_horaire numeric,
    rupture_anticipee boolean DEFAULT false NOT NULL,
    CONSTRAINT contrat_date_fin_obligatoire CHECK (((type_contrat = 'CDI'::text) OR (date_fin IS NOT NULL))),
    CONSTRAINT historique_contrats_type_periode_check CHECK ((type_periode = ANY (ARRAY['civil'::text, 'decalee'::text])))
);


--
-- Name: contrats_du_collab(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.contrats_du_collab(p_collab_id text) RETURNS SETOF public.historique_contrats
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select * from historique_contrats
  where collab_id = p_collab_id
  order by date_debut;
$$;


--
-- Name: contrats_incoherences(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.contrats_incoherences() RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select count(*)::integer
  from historique_contrats h
  join collaborateurs c on c.collab_id = h.collab_id
  where h.date_fin is not null
    and h.date_fin < current_date
    and coalesce(c.actif, false)
    and not h.rupture_anticipee
    and not exists (
      select 1 from historique_contrats a
      where a.collab_id = h.collab_id
        and a.id <> h.id
        and a.date_debut <= current_date
        and (a.date_fin is null or a.date_fin >= current_date)
    );
$$;


--
-- Name: contrats_liste(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.contrats_liste(p_historique boolean DEFAULT false) RETURNS TABLE(id bigint, collab_id text, nom_complet text, collab_actif boolean, collab_role text, structure text, type_contrat text, type_periode text, date_debut date, date_fin date, heures_hebdo numeric, matricule_silae text, taux_horaire numeric, rupture_anticipee boolean, est_courant boolean, etat text, jours_avant_fin integer, a_une_suite boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with base as (
    select h.*, c.actif as c_actif, c.role as c_role,
           coalesce(c.nom_affiche, c.prenom || ' ' || c.nom) as c_nom,
           c.nom as c_nom_tri,
           exists (
             select 1 from historique_contrats s
             where s.collab_id = h.collab_id
               and s.date_debut > h.date_debut
           ) as suite,
           exists (
             select 1 from historique_contrats a
             where a.collab_id = h.collab_id
               and a.id <> h.id
               and a.date_debut <= current_date
               and (a.date_fin is null or a.date_fin >= current_date)
           ) as autre_en_cours,
           (h.date_debut <= current_date
             and (h.date_fin is null or h.date_fin >= current_date)) as courant
    from historique_contrats h
    left join collaborateurs c on c.collab_id = h.collab_id
  )
  select id, collab_id, c_nom, c_actif, c_role, structure, type_contrat,
         type_periode, date_debut, date_fin, heures_hebdo, matricule_silae,
         taux_horaire, rupture_anticipee, courant,
         case
           when rupture_anticipee then 'rupture'
           when date_fin is not null and date_fin < current_date
                and date_fin >= current_date - 7
                and not suite then 'echu_sans_suite'
           when date_fin is not null and date_fin < current_date then 'termine'
           when date_debut > current_date then 'a_venir'
           when date_fin is null then 'sans_fin'
           when date_fin <= current_date + 10 and not suite then 'fin_proche'
           else 'en_cours'
         end,
         case when date_fin is null then null
              else (date_fin - current_date)::integer end,
         suite
  from base
  where p_historique
     or courant
     or (
          date_fin is not null
          and date_fin < current_date
          and date_fin >= current_date - 7
          and not rupture_anticipee
          and not suite
        )
  order by
    case when date_fin is null then 1 else 0 end,
    date_fin,
    coalesce(c_nom, c_nom_tri);
$$;


--
-- Name: contrats_pour_paie(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.contrats_pour_paie(p_collab_ids text[]) RETURNS TABLE(collab_id text, date_debut date, date_fin date, structure text, type_contrat text, heures_hebdo numeric, type_periode text, matricule_silae text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select collab_id, date_debut, date_fin, structure, type_contrat,
         heures_hebdo, type_periode, matricule_silae
  from historique_contrats
  where collab_id = any(p_collab_ids);
$$;


--
-- Name: creer_collaborateur_avec_contrat(text, text, text, text, text, text, text, text, text, text, numeric, text, date, boolean, text, numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.creer_collaborateur_avec_contrat(p_collab_id text, p_token text, p_prenom text, p_nom text, p_nom_affiche text, p_email text, p_structure text, p_equipe_id text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_statut text, p_date_activation date, p_actif boolean, p_matricule_silae text, p_taux_horaire numeric DEFAULT NULL::numeric, p_date_fin date DEFAULT NULL::date) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if p_date_fin is not null and p_date_fin < p_date_activation then
    raise exception 'Date de fin % anterieure au debut % du contrat', p_date_fin, p_date_activation;
  end if;

  insert into collaborateurs (
    collab_id, token, prenom, nom, nom_affiche, email, structure, equipe_id,
    type_contrat, type_periode, heures_hebdo, statut, date_activation, actif, matricule_silae
  ) values (
    p_collab_id, p_token, p_prenom, p_nom, p_nom_affiche, p_email, p_structure, p_equipe_id,
    p_type_contrat, p_type_periode, p_heures_hebdo, p_statut, p_date_activation, p_actif, p_matricule_silae
  );

  insert into historique_contrats (
    collab_id, date_debut, date_fin, structure, type_contrat, type_periode, heures_hebdo, matricule_silae, taux_horaire
  ) values (
    p_collab_id, p_date_activation, p_date_fin, p_structure, p_type_contrat, p_type_periode, p_heures_hebdo, p_matricule_silae, p_taux_horaire
  );

  return p_collab_id;
end;
$$;


--
-- Name: derniere_saisie_par_collab(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.derniere_saisie_par_collab() RETURNS TABLE(collab_id text, derniere_saisie date)
    LANGUAGE sql STABLE
    AS $$
  select j.collab_id, max(j.date_jour)
  from public.jours j
  where coalesce(j.c1_debut, '') <> ''
     or coalesce(j.c2_debut, '') <> ''
     or coalesce(j.c3_debut, '') <> ''
     or j.type_jour in ('CP','AT','CS')
  group by j.collab_id;
$$;


--
-- Name: equipes_liste(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.equipes_liste() RETURNS TABLE(equipe_id text, nom_equipe text, nom_manager text, manager_token text, actif boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select equipe_id, nom_equipe, nom_manager, manager_token, actif
  from equipes
  order by nom_equipe;
$$;


--
-- Name: evp_synthese(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.evp_synthese(p_periode_id text, p_structure text DEFAULT NULL::text) RETURNS TABLE(collab_id text, nom_complet text, structure text, matricule_silae text, numero_securite_sociale text, type_jour text, date_debut date, date_fin date, nb_jours integer, nb_jours_travailles integer, nb_heures_total numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with base as (
    select
      pd.collab_id,
      pd.date_jour,
      coalesce(pd.type_jour_valide, pd.type_jour) as type_jour,
      coalesce(pd.heures_valide, pd.total_heures, 0) as heures
    from paie_detail pd
    where pd.periode_id = p_periode_id
  ),
  pertinent as (
    select * from base
    where type_jour in ('AT', 'CP', 'CS')
       or (type_jour = 'travaillée' and heures > 0)
  ),
  marque as (
    select
      p.*,
      case
        when p.type_jour <> lag(p.type_jour) over (partition by p.collab_id order by p.date_jour)
        then 1 else 0
      end as rupture
    from pertinent p
  ),
  groupe as (
    select
      m.*,
      sum(rupture) over (partition by m.collab_id order by m.date_jour) as grp
    from marque m
  ),
  plages as (
    select
      collab_id, type_jour,
      min(date_jour) as date_debut,
      max(date_jour) as date_fin,
      count(*) as nb_jours
    from groupe
    where type_jour in ('AT', 'CP', 'CS')
    group by collab_id, type_jour, grp
  ),
  totaux as (
    select
      collab_id,
      count(*) filter (where type_jour = 'travaillée' and heures > 0) as nb_jours_travailles,
      sum(heures) filter (where type_jour in ('travaillée', 'AT', 'CS')) as nb_heures_total
    from base
    group by collab_id
  )
  select
    t.collab_id,
    coalesce(c.nom_affiche, c.prenom || ' ' || c.nom),
    c.structure,
    c.matricule_silae, c.numero_securite_sociale,
    p.type_jour, p.date_debut, p.date_fin, p.nb_jours,
    t.nb_jours_travailles, t.nb_heures_total
  from totaux t
  join collaborateurs c on c.collab_id = t.collab_id
  left join plages p on p.collab_id = t.collab_id
  where p_structure is null or c.structure = p_structure
  order by
    coalesce(c.nom_affiche, c.nom),
    case p.type_jour when 'AT' then 1 when 'CP' then 2 when 'CS' then 3 end nulls last,
    p.date_debut;
$$;


--
-- Name: generer_jour_aujourdhui(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generer_jour_aujourdhui() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: generer_periodes_suivantes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generer_periodes_suivantes() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
                       then ' — ⚠️  collision(s) : des périodes attendues n''ont pas été créées (voir warnings)'
                       else '' end);
  end;
  $$;


--
-- Name: journal_archives(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.journal_archives() RETURNS TABLE(id bigint, edite_le timestamp with time zone, edite_par text, borne_debut timestamp with time zone, contenu text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select id, edite_le, edite_par, borne_debut, contenu
  from journal_editions
  order by edite_le desc;
$$;


--
-- Name: journal_cloturer(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.journal_cloturer(p_par text, p_contenu text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_borne timestamptz;
  v_id bigint;
begin
  select coalesce(max(edite_le), '2000-01-01'::timestamptz)
    into v_borne from journal_editions;

  insert into journal_editions (edite_par, borne_debut, contenu)
  values (p_par, v_borne, p_contenu)
  returning id into v_id;

  return v_id;
end;
$$;


--
-- Name: journal_mouvements(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.journal_mouvements(p_depuis timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE(structure text, destination text, collab_id text, nom_complet text, matricule_silae text, contrat_id bigint, mouvement text, date_debut date, date_fin date, heures_hebdo numeric, taux_horaire numeric, type_contrat text, rupture_anticipee boolean, cree boolean, borne timestamp with time zone, a_une_suite boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with borne as (
    select coalesce(
      p_depuis,
      (select coalesce(max(edite_le), '2000-01-01'::timestamptz) from journal_editions)
    ) as depuis
  )
  select
    x.structure, x.destination, x.collab_id, x.nom_complet, x.matricule_silae,
    x.contrat_id, x.mouvement, x.date_debut, x.date_fin, x.heures_hebdo,
    x.taux_horaire, x.type_contrat, x.rupture_anticipee, x.cree, x.borne,
    x.a_une_suite
  from (

    -- 1) écritures (création / modification) depuis la borne. Inchangé.
    select
      h.structure,
      case when h.type_contrat = 'TESA' then 'MSA' else 'SILAE' end as destination,
      h.collab_id,
      coalesce(c.nom_affiche, c.prenom || ' ' || c.nom) as nom_complet,
      case when h.type_contrat = 'TESA' then null else c.matricule_silae end as matricule_silae,
      h.id as contrat_id,
      case when h.created_at > b.depuis then 'creation' else 'modification' end as mouvement,
      h.date_debut, h.date_fin, h.heures_hebdo, h.taux_horaire,
      h.type_contrat, h.rupture_anticipee,
      (h.created_at > b.depuis) as cree,
      b.depuis as borne,
      exists (
        select 1 from historique_contrats s
        where s.collab_id = h.collab_id and s.date_debut > h.date_debut
      ) as a_une_suite,
      coalesce(c.nom_affiche, c.nom) as tri_nom
    from historique_contrats h
    join collaborateurs c on c.collab_id = h.collab_id
    cross join borne b
    where h.created_at > b.depuis
       or (h.modifie_le is not null and h.modifie_le > b.depuis)

    union all

    -- 2) fins de contrat. date_fin >= borne (INCLUSIF, corrigé) et strictement passée.
    select
      h.structure,
      case when h.type_contrat = 'TESA' then 'MSA' else 'SILAE' end,
      h.collab_id,
      coalesce(c.nom_affiche, c.prenom || ' ' || c.nom),
      case when h.type_contrat = 'TESA' then null else c.matricule_silae end,
      h.id,
      'fin',
      h.date_debut, h.date_fin, h.heures_hebdo, h.taux_horaire,
      h.type_contrat, h.rupture_anticipee,
      false,
      b.depuis,
      exists (
        select 1 from historique_contrats s
        where s.collab_id = h.collab_id and s.date_debut > h.date_debut
      ),
      coalesce(c.nom_affiche, c.nom)
    from historique_contrats h
    join collaborateurs c on c.collab_id = h.collab_id
    cross join borne b
    where h.date_fin is not null
      and h.date_fin < (now() at time zone 'Europe/Paris')::date
      and h.date_fin >= b.depuis::date
      and coalesce(h.rupture_anticipee, false) = false

    union all

    -- 3) ruptures anticipées. Même correctif >=.
    select
      h.structure,
      case when h.type_contrat = 'TESA' then 'MSA' else 'SILAE' end,
      h.collab_id,
      coalesce(c.nom_affiche, c.prenom || ' ' || c.nom),
      case when h.type_contrat = 'TESA' then null else c.matricule_silae end,
      h.id,
      'rupture',
      h.date_debut, h.date_fin, h.heures_hebdo, h.taux_horaire,
      h.type_contrat, h.rupture_anticipee,
      false,
      b.depuis,
      exists (
        select 1 from historique_contrats s
        where s.collab_id = h.collab_id and s.date_debut > h.date_debut
      ),
      coalesce(c.nom_affiche, c.nom)
    from historique_contrats h
    join collaborateurs c on c.collab_id = h.collab_id
    cross join borne b
    where h.date_fin is not null
      and h.date_fin < (now() at time zone 'Europe/Paris')::date
      and h.date_fin >= b.depuis::date
      and h.rupture_anticipee = true

  ) x
  order by x.structure, x.destination, x.tri_nom, x.date_debut;
$$;


--
-- Name: journal_tache_creer(text, text, text, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.journal_tache_creer(p_objet text, p_tiers text, p_collab_id text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_date_echeance date DEFAULT NULL::date) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_id bigint;
begin
  insert into journal_taches (collab_id, objet, tiers, note, date_echeance)
  values (p_collab_id, p_objet, p_tiers, p_note, p_date_echeance)
  returning id into v_id;

  return v_id;
end;
$$;


--
-- Name: journal_tache_creer(text, text, text, text, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.journal_tache_creer(p_objet text, p_tiers text, p_collab_id text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_date_echeance date DEFAULT NULL::date, p_remarque text DEFAULT NULL::text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_id bigint;
begin
  insert into journal_taches (collab_id, objet, tiers, note, date_echeance, remarque)
  values (p_collab_id, p_objet, p_tiers, p_note, p_date_echeance, p_remarque)
  returning id into v_id;

  return v_id;
end;
$$;


--
-- Name: journal_tache_traiter(bigint, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.journal_tache_traiter(p_id bigint, p_statut text, p_fait_par text DEFAULT NULL::text, p_remarque text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if p_statut not in ('faite', 'sans_objet', 'a_faire') then
    raise exception 'statut invalide : % (attendu faite, sans_objet ou a_faire)', p_statut;
  end if;

  update journal_taches
  set statut = p_statut,
      fait_le = case when p_statut = 'a_faire' then null else now() end,
      fait_par = case when p_statut = 'a_faire' then null else p_fait_par end,
      remarque = coalesce(p_remarque, remarque)
  where id = p_id;

  if not found then
    raise exception 'tâche % introuvable', p_id;
  end if;
end;
$$;


--
-- Name: journal_taches_liste(text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.journal_taches_liste(p_statut text DEFAULT 'a_faire'::text, p_mouvement text DEFAULT NULL::text, p_type_contrat text DEFAULT NULL::text, p_tiers text DEFAULT NULL::text, p_structure text DEFAULT NULL::text) RETURNS TABLE(id bigint, collab_id text, nom_complet text, matricule_silae text, numero_securite_sociale text, telephone text, email text, contrat_id bigint, structure text, type_contrat text, periode_id text, nom_periode text, mouvement text, objet text, tiers text, note text, date_echeance date, statut text, fait_le timestamp with time zone, fait_par text, remarque text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select
    t.id, t.collab_id,
    coalesce(c.nom_affiche, c.prenom || ' ' || c.nom) as nom_complet,
    c.matricule_silae, c.numero_securite_sociale, c.telephone, c.email,
    t.contrat_id,
    coalesce(h.structure, hd.structure) as structure,
    coalesce(h.type_contrat, hd.type_contrat) as type_contrat,
    t.periode_id, p.nom_periode,
    t.mouvement, t.objet, t.tiers, t.note, t.date_echeance,
    t.statut, t.fait_le, t.fait_par, t.remarque
  from journal_taches t
  left join collaborateurs c on c.collab_id = t.collab_id
  left join historique_contrats h on h.id = t.contrat_id
  left join lateral (
    select hc.structure, hc.type_contrat
    from historique_contrats hc
    where hc.collab_id = t.collab_id
    order by hc.date_debut desc
    limit 1
  ) hd on h.id is null and t.collab_id is not null
  left join periodes p on p.periode_id = t.periode_id
  where (p_statut is null or t.statut = p_statut)
    and (p_mouvement is null or t.mouvement = p_mouvement)
    and (p_type_contrat is null or coalesce(h.type_contrat, hd.type_contrat) = p_type_contrat)
    and (p_tiers is null or t.tiers = p_tiers)
    and (p_structure is null or coalesce(h.structure, hd.structure) = p_structure)
  order by t.date_echeance nulls last, nom_complet nulls last;
$$;


--
-- Name: manager_equipe(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_equipe(p_manager_token text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_equipe record;
  v_membres jsonb;
  v_jours jsonb;
begin
  select equipe_id, nom_equipe, nom_manager, actif
    into v_equipe
  from equipes
  where manager_token = p_manager_token;

  if v_equipe.equipe_id is null or coalesce(v_equipe.actif, false) = false then
    return jsonb_build_object('ok', false, 'error', 'acces_refuse');
  end if;

  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) into v_membres
  from (
    select collab_id, prenom, nom, nom_affiche, structure,
           type_contrat, heures_hebdo, actif, equipe_id
    from collaborateurs
    where equipe_id = v_equipe.equipe_id and actif = true
    order by nom_affiche
  ) m;

  select coalesce(jsonb_agg(to_jsonb(j)), '[]'::jsonb) into v_jours
  from (
    select * from jours
    where collab_id in (
      select collab_id from collaborateurs
      where equipe_id = v_equipe.equipe_id and actif = true
    )
    and date_jour >= current_date - 30
    order by date_jour desc
  ) j;

  return jsonb_build_object(
    'ok', true,
    'equipe', jsonb_build_object(
      'equipe_id', v_equipe.equipe_id,
      'nom_equipe', v_equipe.nom_equipe,
      'nom_manager', v_equipe.nom_manager),
    'membres', v_membres,
    'jours', v_jours);
end;
$$;


--
-- Name: materialiser_journal_taches(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.materialiser_journal_taches() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_depuis constant timestamptz := '2026-09-15 00:00:00+00'::timestamptz;
  v_depuis_cloture constant date := '2026-09-20'::date;
  v_nb integer;
begin
  with mouvements as (
    select * from journal_mouvements(v_depuis)
  ),
  candidats as (
    select
      m.collab_id,
      m.contrat_id,
      m.mouvement,
      null::text as periode_id,
      r.id as regle_id,
      r.objet,
      r.tiers,
      r.note,
      case
        when r.echeance_jours is null then null
        else
          (case when m.mouvement in ('creation','modification') then m.date_debut else m.date_fin end)
          + (case when r.echeance_sens = 'avant' then -r.echeance_jours else r.echeance_jours end)
      end as date_echeance
    from mouvements m
    join journal_regles r
      on r.actif = true
     and r.mouvement = m.mouvement
     and (r.type_contrat is null or r.type_contrat = m.type_contrat)
     and (r.avec_suite is null or r.avec_suite = m.a_une_suite)

    union all

    -- Clôtures de période, portée 'collaborateur' : une tâche par personne
    -- présente dans paie_detail pour la période clôturée.
    select
      pd.collab_id,
      null::bigint as contrat_id,
      'cloture_periode' as mouvement,
      p.periode_id,
      r.id,
      r.objet,
      r.tiers,
      r.note,
      case
        when r.echeance_jours is null then null
        else p.date_cloture + (case when r.echeance_sens = 'avant' then -r.echeance_jours else r.echeance_jours end)
      end
    from periodes p
    join journal_regles r
      on r.actif = true
     and r.mouvement = 'cloture_periode'
     and r.portee = 'collaborateur'
     and (r.type_periode is null or r.type_periode = p.type_periode)
    join (select distinct periode_id, collab_id from paie_detail) pd
      on pd.periode_id = p.periode_id
    where p.statut = 'cloturee'
      and p.date_cloture is not null
      and p.date_cloture >= v_depuis_cloture

    union all

    -- Clôtures de période, portée 'periode' : une seule tâche, sans collaborateur.
    select
      null::text as collab_id,
      null::bigint as contrat_id,
      'cloture_periode' as mouvement,
      p.periode_id,
      r.id,
      r.objet,
      r.tiers,
      r.note,
      case
        when r.echeance_jours is null then null
        else p.date_cloture + (case when r.echeance_sens = 'avant' then -r.echeance_jours else r.echeance_jours end)
      end
    from periodes p
    join journal_regles r
      on r.actif = true
     and r.mouvement = 'cloture_periode'
     and r.portee = 'periode'
     and (r.type_periode is null or r.type_periode = p.type_periode)
    where p.statut = 'cloturee'
      and p.date_cloture is not null
      and p.date_cloture >= v_depuis_cloture
  ),
  inseres as (
    insert into journal_taches
      (collab_id, contrat_id, mouvement, regle_id, periode_id, objet, tiers, note, date_echeance)
    select collab_id, contrat_id, mouvement, regle_id, periode_id, objet, tiers, note, date_echeance
    from candidats
    on conflict do nothing
    returning 1
  )
  select count(*) into v_nb from inseres;

  return v_nb;
end;
$$;


--
-- Name: modifier_contrat(bigint, date, date, text, text, text, numeric, text, text, numeric, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.modifier_contrat(p_id bigint, p_date_debut date, p_date_fin date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_modifie_par text, p_taux_horaire numeric DEFAULT NULL::numeric, p_rupture_anticipee boolean DEFAULT NULL::boolean) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_collab_id text;
  v_date_debut_actuelle date;
  v_structure_actuelle text;
  v_type_periode_actuelle text;
  v_chevauche bigint;
begin
  select collab_id, date_debut, structure, type_periode
    into v_collab_id, v_date_debut_actuelle, v_structure_actuelle, v_type_periode_actuelle
  from historique_contrats
  where id = p_id;
  if v_collab_id is null then
    raise exception 'Ligne de contrat introuvable (id %)', p_id;
  end if;

  if (p_structure is distinct from v_structure_actuelle
      or p_type_periode is distinct from v_type_periode_actuelle)
     and v_date_debut_actuelle <= current_date then
    raise exception 'Structure et type de periode non modifiables sur un contrat deja commence. Cloturez et recreez.';
  end if;

  if p_date_fin is not null and p_date_fin < p_date_debut then
    raise exception 'Date de fin % anterieure au debut % du contrat', p_date_fin, p_date_debut;
  end if;

  select id into v_chevauche
  from historique_contrats
  where collab_id = v_collab_id
    and id <> p_id
    and p_date_debut <= coalesce(date_fin, 'infinity'::date)
    and coalesce(p_date_fin, 'infinity'::date) >= date_debut
  limit 1;
  if v_chevauche is not null then
    raise exception 'La periode chevauche un autre contrat du collaborateur (ligne %)', v_chevauche;
  end if;

  update historique_contrats
  set date_debut        = p_date_debut,
      date_fin          = p_date_fin,
      structure         = p_structure,
      type_contrat      = p_type_contrat,
      type_periode      = p_type_periode,
      heures_hebdo      = p_heures_hebdo,
      matricule_silae   = p_matricule_silae,
      taux_horaire      = coalesce(p_taux_horaire, taux_horaire),
      rupture_anticipee = coalesce(p_rupture_anticipee, rupture_anticipee),
      modifie_le        = now(),
      modifie_par       = p_modifie_par
  where id = p_id;

  perform rafraichir_fiche_collab(v_collab_id);
  return p_id::text;
end;
$$;


--
-- Name: ouvrir_geler_periodes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ouvrir_geler_periodes() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: rafraichir_fiche_collab(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rafraichir_fiche_collab(p_collab_id text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_count int;
  v_structure text;
  v_type_contrat text;
  v_type_periode text;
  v_heures_hebdo numeric;
  v_matricule_silae text;
begin
  -- compter les lignes courantes (date_debut <= aujourd'hui ET (date_fin null OU >= aujourd'hui))
  select count(*) into v_count
  from historique_contrats
  where collab_id = p_collab_id
    and date_debut <= current_date
    and (date_fin is null or date_fin >= current_date);

  -- 0 ligne courante : trou OU que du futur -> on ne touche PAS la fiche, on signale
  if v_count = 0 then
    return 'trou:' || p_collab_id;
  end if;

  -- 2+ lignes courantes : jamais cense arriver (chevauchement) -> aucun departage, on log
  if v_count > 1 then
    raise warning 'rafraichir_fiche_collab: % lignes courantes pour % - chevauchement, fiche NON modifiee', v_count, p_collab_id;
    return 'anomalie:' || p_collab_id;
  end if;

  -- exactement 1 ligne courante : on recopie
  select structure, type_contrat, type_periode, heures_hebdo, matricule_silae
    into v_structure, v_type_contrat, v_type_periode, v_heures_hebdo, v_matricule_silae
  from historique_contrats
  where collab_id = p_collab_id
    and date_debut <= current_date
    and (date_fin is null or date_fin >= current_date);

  update collaborateurs
  set structure       = v_structure,
      type_contrat    = v_type_contrat,
      type_periode    = v_type_periode,
      heures_hebdo    = v_heures_hebdo,
      matricule_silae = v_matricule_silae
  where collab_id = p_collab_id;

  return 'ok:' || p_collab_id;
end;
$$;


--
-- Name: renouveler_contrats_lot(bigint[], date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.renouveler_contrats_lot(p_ids bigint[], p_date_debut date, p_date_fin date, p_par text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  r record;
  v_derniere_fin date;
  v_nb integer := 0;
begin
  if p_date_debut is null or p_date_fin is null then
    raise exception 'Les deux dates sont requises.';
  end if;
  if p_date_fin < p_date_debut then
    raise exception 'La date de fin ne peut pas preceder la date de debut.';
  end if;
  if p_ids is null or array_length(p_ids, 1) is null then
    raise exception 'Aucun contrat selectionne.';
  end if;

  for r in
    select h.id, h.collab_id, h.date_fin, h.structure, h.type_contrat,
           h.type_periode, h.heures_hebdo, h.matricule_silae, h.taux_horaire,
           coalesce(c.nom_affiche, c.prenom || ' ' || c.nom) as nom
    from historique_contrats h
    left join collaborateurs c on c.collab_id = h.collab_id
    where h.id = any(p_ids)
  loop
    if r.date_fin is null then
      raise exception '% n''a pas de date de fin. Posez-la avant de renouveler.', r.nom;
    end if;

    select max(date_fin) into v_derniere_fin
    from historique_contrats where collab_id = r.collab_id;

    if p_date_debut <= v_derniere_fin then
      raise exception '% termine le %, apres la date de debut saisie. Decochez-le ou changez la date.',
        r.nom, to_char(v_derniere_fin, 'DD/MM/YYYY');
    end if;

    if exists (select 1 from historique_contrats
               where collab_id = r.collab_id and date_fin is null) then
      raise exception '% a deja un contrat ouvert.', r.nom;
    end if;

    insert into historique_contrats (
      collab_id, date_debut, date_fin, structure, type_contrat,
      type_periode, heures_hebdo, matricule_silae, taux_horaire)
    values (
      r.collab_id, p_date_debut, p_date_fin, r.structure, r.type_contrat,
      r.type_periode, r.heures_hebdo, r.matricule_silae, r.taux_horaire);

    perform rafraichir_fiche_collab(r.collab_id);
    v_nb := v_nb + 1;
  end loop;

  return v_nb;
end;
$$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: supprimer_contrat(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.supprimer_contrat(p_id bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_collab_id text;
  v_date_debut date;
begin
  -- retrouver la ligne
  select collab_id, date_debut into v_collab_id, v_date_debut
  from historique_contrats
  where id = p_id;
  if v_collab_id is null then
    raise exception 'Ligne de contrat introuvable (id %)', p_id;
  end if;

  -- garde : seul un contrat A VENIR peut etre supprime
  if v_date_debut <= current_date then
    raise exception 'Seul un contrat a venir peut etre supprime. Un contrat commence ou termine se cloture, il ne s efface pas.';
  end if;

  -- suppression
  delete from historique_contrats where id = p_id;

  -- resynchroniser la fiche (par securite)
  perform rafraichir_fiche_collab(v_collab_id);

  return p_id::text;
end;
$$;


--
-- Name: synchroniser_activite(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.synchroniser_activite() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_actives integer;
  v_inactives integer;
  v_taches integer;
  v_taches_regles integer;
begin
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
  premiere as (
    select a.collab_id
    from activ a
    where not exists (
      select 1 from historique_contrats p
      where p.collab_id = a.collab_id
        and p.date_fin is not null
        and p.date_fin < v_today
    )
  ),
  ins as (
    insert into journal_taches (collab_id, mouvement, objet, tiers, statut)
    select p.collab_id, 'activation', 'Envoyer le lien de l''appli', 'EMPLOYE', 'a_faire'
    from premiere p
    where not exists (
      select 1 from journal_taches t
      where t.collab_id = p.collab_id
        and t.mouvement = 'activation'
        and t.statut = 'a_faire'
        and t.regle_id is null
    )
    returning 1
  ),
  ins_regles as (
    insert into journal_taches
      (collab_id, mouvement, regle_id, objet, tiers, note, date_echeance, statut)
    select p.collab_id, 'activation', r.id, r.objet, r.tiers, r.note,
           case when r.echeance_jours is null then null
                when r.echeance_sens = 'avant' then v_today - r.echeance_jours
                else v_today + r.echeance_jours end,
           'a_faire'
    from premiere p
    join collaborateurs c on c.collab_id = p.collab_id
    join journal_regles r
      on r.actif
     and r.mouvement = 'activation'
     and (r.type_contrat is null or r.type_contrat = c.type_contrat)
    where not exists (
      select 1 from journal_taches t
      where t.collab_id = p.collab_id
        and t.mouvement = 'activation'
        and t.regle_id = r.id
    )
    returning 1
  )
  select (select count(*) from activ),
         (select count(*) from ins),
         (select count(*) from ins_regles)
  into v_actives, v_taches, v_taches_regles;

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
      || v_taches || ' tâche(s) lien, ' || v_taches_regles || ' tâche(s) règle';
end;
$$;


--
-- Name: trigger_quotidien(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trigger_quotidien() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
  $$;


--
-- Name: verifier_admin(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.verifier_admin(p_token text) RETURNS text
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select nom from admins where token = p_token and actif = true limit 1;
$$;


--
-- Name: admins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admins (
    admin_id text NOT NULL,
    nom text,
    token text,
    actif boolean DEFAULT true
);


--
-- Name: equipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.equipes (
    equipe_id text NOT NULL,
    nom_equipe text NOT NULL,
    nom_manager text,
    manager_token text,
    actif boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: historique_contrats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.historique_contrats ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.historique_contrats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: journal_editions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_editions (
    id bigint NOT NULL,
    edite_le timestamp with time zone DEFAULT now() NOT NULL,
    edite_par text,
    borne_debut timestamp with time zone,
    contenu text
);


--
-- Name: journal_editions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.journal_editions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.journal_editions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: journal_regles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_regles (
    id bigint NOT NULL,
    mouvement text NOT NULL,
    type_contrat text,
    avec_suite boolean,
    objet text NOT NULL,
    tiers text NOT NULL,
    echeance_jours integer,
    echeance_sens text,
    note text,
    ordre integer DEFAULT 0 NOT NULL,
    actif boolean DEFAULT true NOT NULL,
    cree_le timestamp with time zone DEFAULT now() NOT NULL,
    modifie_le timestamp with time zone,
    modifie_par text,
    type_periode text,
    portee text,
    CONSTRAINT journal_regles_echeance_jours_positif_chk CHECK (((echeance_jours IS NULL) OR (echeance_jours >= 0))),
    CONSTRAINT journal_regles_echeance_paire_chk CHECK ((((echeance_jours IS NULL) AND (echeance_sens IS NULL)) OR ((echeance_jours IS NOT NULL) AND (echeance_sens IS NOT NULL)))),
    CONSTRAINT journal_regles_echeance_sens_chk CHECK (((echeance_sens IS NULL) OR (echeance_sens = ANY (ARRAY['avant'::text, 'apres'::text])))),
    CONSTRAINT journal_regles_mouvement_chk CHECK ((mouvement = ANY (ARRAY['creation'::text, 'modification'::text, 'fin'::text, 'rupture'::text, 'cloture_periode'::text, 'activation'::text]))),
    CONSTRAINT journal_regles_portee_chk CHECK ((((mouvement <> 'cloture_periode'::text) AND (portee IS NULL)) OR ((mouvement = 'cloture_periode'::text) AND (portee = ANY (ARRAY['collaborateur'::text, 'periode'::text]))))),
    CONSTRAINT journal_regles_tiers_chk CHECK ((tiers = ANY (ARRAY['MSA'::text, 'SILAE'::text, 'GESTIONNAIRE_PAIE'::text, 'EMPLOYE'::text, 'FRANCE_TRAVAIL'::text, 'AUTRE'::text]))),
    CONSTRAINT journal_regles_type_contrat_chk CHECK (((type_contrat IS NULL) OR (type_contrat = ANY (ARRAY['TESA'::text, 'CDI'::text, 'CDD'::text])))),
    CONSTRAINT journal_regles_type_periode_chk CHECK (((type_periode IS NULL) OR (type_periode = ANY (ARRAY['civil'::text, 'decalee'::text]))))
);


--
-- Name: TABLE journal_regles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.journal_regles IS 'Règles du journal des déclarations : une tâche administrative déclenchée par un mouvement de contrat. Jointes au mouvement à l''affichage, jamais persistées par mouvement.';


--
-- Name: journal_regles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.journal_regles ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.journal_regles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: journal_taches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_taches (
    id bigint NOT NULL,
    collab_id text,
    contrat_id bigint,
    mouvement text,
    regle_id bigint,
    objet text NOT NULL,
    tiers text NOT NULL,
    note text,
    date_echeance date,
    statut text DEFAULT 'a_faire'::text NOT NULL,
    fait_le timestamp with time zone,
    fait_par text,
    remarque text,
    cree_le timestamp with time zone DEFAULT now() NOT NULL,
    periode_id text,
    CONSTRAINT journal_taches_mouvement_chk CHECK (((mouvement IS NULL) OR (mouvement = ANY (ARRAY['creation'::text, 'modification'::text, 'fin'::text, 'rupture'::text, 'cloture_periode'::text, 'activation'::text])))),
    CONSTRAINT journal_taches_statut_chk CHECK ((statut = ANY (ARRAY['a_faire'::text, 'faite'::text, 'sans_objet'::text]))),
    CONSTRAINT journal_taches_statut_coherence_chk CHECK ((((statut = 'a_faire'::text) AND (fait_le IS NULL) AND (fait_par IS NULL)) OR ((statut = ANY (ARRAY['faite'::text, 'sans_objet'::text])) AND (fait_le IS NOT NULL) AND (fait_par IS NOT NULL)))),
    CONSTRAINT journal_taches_tiers_chk CHECK ((tiers = ANY (ARRAY['MSA'::text, 'SILAE'::text, 'GESTIONNAIRE_PAIE'::text, 'EMPLOYE'::text, 'FRANCE_TRAVAIL'::text, 'AUTRE'::text])))
);


--
-- Name: TABLE journal_taches; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.journal_taches IS 'Tâches administratives persistées du journal des déclarations. Remplace la borne/clôture. Matérialisées idempotemment à l''ouverture du journal (unicité contrat_id+mouvement+regle_id). Indépendantes de leur règle : objet/tiers/note/échéance recopiés à la création.';


--
-- Name: journal_taches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.journal_taches ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.journal_taches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: jours; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jours (
    jour_id text NOT NULL,
    collab_id text,
    date_jour date,
    jour_semaine text,
    periode_id text,
    type_jour text,
    c1_debut text,
    c1_fin text,
    c2_debut text,
    c2_fin text,
    c3_debut text,
    c3_fin text,
    commentaire text,
    total_heures numeric DEFAULT 0,
    total_hebdo_prog numeric DEFAULT 0,
    nb_modifications integer DEFAULT 0,
    date_derniere_modif text,
    remarque_manager text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: paie_detail; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.paie_detail (
    id bigint NOT NULL,
    periode_id text NOT NULL,
    collab_id text NOT NULL,
    date_jour date NOT NULL,
    jour_semaine text,
    date_cloture timestamp with time zone DEFAULT now(),
    type_jour text,
    c1_debut text,
    c1_fin text,
    c2_debut text,
    c2_fin text,
    c3_debut text,
    c3_fin text,
    total_heures numeric,
    commentaire text,
    remarque_manager text,
    total_hebdo_prog numeric,
    nb_modifications integer,
    date_derniere_modif text,
    type_jour_valide text,
    heures_valide numeric,
    ajuste_admin boolean DEFAULT false,
    note_admin text,
    date_ajuste_admin timestamp with time zone,
    c1_debut_valide text,
    c1_fin_valide text,
    c2_debut_valide text,
    c2_fin_valide text,
    c3_debut_valide text,
    c3_fin_valide text
);


--
-- Name: paie_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.paie_detail ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.paie_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: periodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.periodes (
    periode_id text NOT NULL,
    nom_periode text,
    type_periode text,
    date_debut date,
    date_fin date,
    date_cloture date,
    statut text DEFAULT 'planifiee'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: recap_paie; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recap_paie (
    id bigint NOT NULL,
    periode_id text NOT NULL,
    collab_id text NOT NULL,
    nom_affiche text,
    heures_travaillees numeric,
    heures_at numeric,
    heures_cs numeric,
    nb_cp integer,
    nb_jours_travailles integer,
    statut_validation text,
    date_validation text,
    statut_signature text,
    note_admin text,
    created_at timestamp with time zone DEFAULT now(),
    nb_at integer DEFAULT 0,
    nb_cs integer DEFAULT 0,
    date_fin_validation date
);


--
-- Name: COLUMN recap_paie.date_fin_validation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recap_paie.date_fin_validation IS 'Cloture partielle : borne de validation pour un collab parti en cours de periode. NULL = validation normale. Les jours au-dela sont ecartes a l''import de periode.';


--
-- Name: recap_paie_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recap_paie ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.recap_paie_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: structures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.structures (
    structure_id text,
    code_structure text NOT NULL,
    nom_legal text,
    adresse text,
    siret text,
    siege text
);


--
-- Name: admins admins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admins
    ADD CONSTRAINT admins_pkey PRIMARY KEY (admin_id);


--
-- Name: admins admins_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admins
    ADD CONSTRAINT admins_token_key UNIQUE (token);


--
-- Name: collaborateurs collaborateurs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaborateurs
    ADD CONSTRAINT collaborateurs_pkey PRIMARY KEY (collab_id);


--
-- Name: collaborateurs collaborateurs_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaborateurs
    ADD CONSTRAINT collaborateurs_token_key UNIQUE (token);


--
-- Name: equipes equipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipes
    ADD CONSTRAINT equipes_pkey PRIMARY KEY (equipe_id);


--
-- Name: historique_contrats historique_contrats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historique_contrats
    ADD CONSTRAINT historique_contrats_pkey PRIMARY KEY (id);


--
-- Name: journal_editions journal_editions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_editions
    ADD CONSTRAINT journal_editions_pkey PRIMARY KEY (id);


--
-- Name: journal_regles journal_regles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_regles
    ADD CONSTRAINT journal_regles_pkey PRIMARY KEY (id);


--
-- Name: journal_taches journal_taches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_taches
    ADD CONSTRAINT journal_taches_pkey PRIMARY KEY (id);


--
-- Name: jours jours_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jours
    ADD CONSTRAINT jours_pkey PRIMARY KEY (jour_id);


--
-- Name: paie_detail paie_detail_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.paie_detail
    ADD CONSTRAINT paie_detail_pkey PRIMARY KEY (id);


--
-- Name: paie_detail paie_detail_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.paie_detail
    ADD CONSTRAINT paie_detail_unique UNIQUE (periode_id, collab_id, date_jour);


--
-- Name: periodes periodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodes
    ADD CONSTRAINT periodes_pkey PRIMARY KEY (periode_id);


--
-- Name: recap_paie recap_paie_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recap_paie
    ADD CONSTRAINT recap_paie_pkey PRIMARY KEY (id);


--
-- Name: recap_paie recap_paie_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recap_paie
    ADD CONSTRAINT recap_paie_unique UNIQUE (periode_id, collab_id);


--
-- Name: structures structures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.structures
    ADD CONSTRAINT structures_pkey PRIMARY KEY (code_structure);


--
-- Name: idx_historique_contrats_collab_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_historique_contrats_collab_date ON public.historique_contrats USING btree (collab_id, date_debut);


--
-- Name: idx_paie_detail_periode_collab; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_paie_detail_periode_collab ON public.paie_detail USING btree (periode_id, collab_id);


--
-- Name: journal_taches_date_echeance_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX journal_taches_date_echeance_idx ON public.journal_taches USING btree (date_echeance);


--
-- Name: journal_taches_statut_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX journal_taches_statut_idx ON public.journal_taches USING btree (statut);


--
-- Name: journal_taches_unique_contrat; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX journal_taches_unique_contrat ON public.journal_taches USING btree (contrat_id, mouvement, regle_id) WHERE (contrat_id IS NOT NULL);


--
-- Name: journal_taches_unique_periode_collab; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX journal_taches_unique_periode_collab ON public.journal_taches USING btree (collab_id, mouvement, regle_id, periode_id) WHERE ((periode_id IS NOT NULL) AND (collab_id IS NOT NULL));


--
-- Name: journal_taches_unique_periode_globale; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX journal_taches_unique_periode_globale ON public.journal_taches USING btree (mouvement, regle_id, periode_id) WHERE ((periode_id IS NOT NULL) AND (collab_id IS NULL));


--
-- Name: historique_contrats historique_contrats_collab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historique_contrats
    ADD CONSTRAINT historique_contrats_collab_id_fkey FOREIGN KEY (collab_id) REFERENCES public.collaborateurs(collab_id);


--
-- Name: journal_taches journal_taches_collab_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_taches
    ADD CONSTRAINT journal_taches_collab_fk FOREIGN KEY (collab_id) REFERENCES public.collaborateurs(collab_id) ON DELETE RESTRICT;


--
-- Name: journal_taches journal_taches_contrat_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_taches
    ADD CONSTRAINT journal_taches_contrat_fk FOREIGN KEY (contrat_id) REFERENCES public.historique_contrats(id) ON DELETE CASCADE;


--
-- Name: journal_taches journal_taches_periode_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_taches
    ADD CONSTRAINT journal_taches_periode_fk FOREIGN KEY (periode_id) REFERENCES public.periodes(periode_id) ON DELETE RESTRICT;


--
-- Name: journal_taches journal_taches_regle_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_taches
    ADD CONSTRAINT journal_taches_regle_fk FOREIGN KEY (regle_id) REFERENCES public.journal_regles(id) ON DELETE SET NULL;


--
-- Name: jours jours_collab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jours
    ADD CONSTRAINT jours_collab_id_fkey FOREIGN KEY (collab_id) REFERENCES public.collaborateurs(collab_id);


--
-- Name: paie_detail paie_detail_collab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.paie_detail
    ADD CONSTRAINT paie_detail_collab_id_fkey FOREIGN KEY (collab_id) REFERENCES public.collaborateurs(collab_id);


--
-- Name: recap_paie recap_paie_collab_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recap_paie
    ADD CONSTRAINT recap_paie_collab_id_fkey FOREIGN KEY (collab_id) REFERENCES public.collaborateurs(collab_id);


--
-- Name: admins; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

--
-- Name: periodes anon update periodes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anon update periodes" ON public.periodes FOR UPDATE TO anon USING (true) WITH CHECK (true);


--
-- Name: collaborateurs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.collaborateurs ENABLE ROW LEVEL SECURITY;

--
-- Name: equipes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.equipes ENABLE ROW LEVEL SECURITY;

--
-- Name: historique_contrats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.historique_contrats ENABLE ROW LEVEL SECURITY;

--
-- Name: collaborateurs insert collaborateurs anon; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insert collaborateurs anon" ON public.collaborateurs FOR INSERT TO anon WITH CHECK (true);


--
-- Name: paie_detail insertion paie_detail; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insertion paie_detail" ON public.paie_detail FOR INSERT WITH CHECK (true);


--
-- Name: recap_paie insertion recap_paie; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insertion recap_paie" ON public.recap_paie FOR INSERT WITH CHECK (true);


--
-- Name: journal_editions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_editions ENABLE ROW LEVEL SECURITY;

--
-- Name: journal_regles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_regles ENABLE ROW LEVEL SECURITY;

--
-- Name: journal_taches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_taches ENABLE ROW LEVEL SECURITY;

--
-- Name: jours; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.jours ENABLE ROW LEVEL SECURITY;

--
-- Name: equipes lecture equipes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "lecture equipes" ON public.equipes FOR SELECT USING (true);


--
-- Name: historique_contrats lecture historique_contrats; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "lecture historique_contrats" ON public.historique_contrats FOR SELECT USING (true);


--
-- Name: jours lecture jours par collab; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "lecture jours par collab" ON public.jours FOR SELECT USING (true);


--
-- Name: paie_detail lecture paie_detail; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "lecture paie_detail" ON public.paie_detail FOR SELECT USING (true);


--
-- Name: collaborateurs lecture par token; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "lecture par token" ON public.collaborateurs FOR SELECT USING (true);


--
-- Name: periodes lecture periodes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "lecture periodes" ON public.periodes FOR SELECT USING (true);


--
-- Name: recap_paie lecture recap_paie; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "lecture recap_paie" ON public.recap_paie FOR SELECT USING (true);


--
-- Name: paie_detail maj paie_detail; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "maj paie_detail" ON public.paie_detail FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: recap_paie maj recap_paie; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "maj recap_paie" ON public.recap_paie FOR UPDATE USING (true) WITH CHECK (true);


--
-- Name: paie_detail; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.paie_detail ENABLE ROW LEVEL SECURITY;

--
-- Name: periodes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.periodes ENABLE ROW LEVEL SECURITY;

--
-- Name: recap_paie; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recap_paie ENABLE ROW LEVEL SECURITY;

--
-- Name: structures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.structures ENABLE ROW LEVEL SECURITY;

--
-- Name: collaborateurs update collaborateurs anon; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update collaborateurs anon" ON public.collaborateurs FOR UPDATE TO anon USING (true) WITH CHECK (true);


--
-- Name: jours update jours; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update jours" ON public.jours FOR UPDATE USING (true);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION activer_collabs_en_attente(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.activer_collabs_en_attente() FROM PUBLIC;


--
-- Name: FUNCTION ajouter_contrat(p_collab_id text, p_date_debut date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_date_fin date, p_taux_horaire numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ajouter_contrat(p_collab_id text, p_date_debut date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_date_fin date, p_taux_horaire numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ajouter_contrat(p_collab_id text, p_date_debut date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_date_fin date, p_taux_horaire numeric) TO service_role;


--
-- Name: FUNCTION candidats_cloture_anticipee(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.candidats_cloture_anticipee() FROM PUBLIC;
GRANT ALL ON FUNCTION public.candidats_cloture_anticipee() TO service_role;


--
-- Name: FUNCTION cloturer_contrat(p_collab_id text, p_date_fin date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cloturer_contrat(p_collab_id text, p_date_fin date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cloturer_contrat(p_collab_id text, p_date_fin date) TO service_role;


--
-- Name: FUNCTION collab_session(p_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.collab_session(p_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.collab_session(p_token text) TO service_role;


--
-- Name: TABLE collaborateurs; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,MAINTAIN ON TABLE public.collaborateurs TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.collaborateurs TO authenticated;
GRANT ALL ON TABLE public.collaborateurs TO service_role;


--
-- Name: FUNCTION collaborateurs_liste(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.collaborateurs_liste() FROM PUBLIC;
GRANT ALL ON FUNCTION public.collaborateurs_liste() TO service_role;


--
-- Name: FUNCTION compteurs_paie_periodes(p_periode_ids text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.compteurs_paie_periodes(p_periode_ids text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.compteurs_paie_periodes(p_periode_ids text[]) TO anon;


--
-- Name: TABLE historique_contrats; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,MAINTAIN ON TABLE public.historique_contrats TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.historique_contrats TO authenticated;
GRANT ALL ON TABLE public.historique_contrats TO service_role;


--
-- Name: FUNCTION contrats_du_collab(p_collab_id text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.contrats_du_collab(p_collab_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.contrats_du_collab(p_collab_id text) TO service_role;


--
-- Name: FUNCTION contrats_incoherences(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.contrats_incoherences() FROM PUBLIC;
GRANT ALL ON FUNCTION public.contrats_incoherences() TO service_role;


--
-- Name: FUNCTION contrats_liste(p_historique boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.contrats_liste(p_historique boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.contrats_liste(p_historique boolean) TO service_role;


--
-- Name: FUNCTION contrats_pour_paie(p_collab_ids text[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.contrats_pour_paie(p_collab_ids text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.contrats_pour_paie(p_collab_ids text[]) TO service_role;


--
-- Name: FUNCTION creer_collaborateur_avec_contrat(p_collab_id text, p_token text, p_prenom text, p_nom text, p_nom_affiche text, p_email text, p_structure text, p_equipe_id text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_statut text, p_date_activation date, p_actif boolean, p_matricule_silae text, p_taux_horaire numeric, p_date_fin date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.creer_collaborateur_avec_contrat(p_collab_id text, p_token text, p_prenom text, p_nom text, p_nom_affiche text, p_email text, p_structure text, p_equipe_id text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_statut text, p_date_activation date, p_actif boolean, p_matricule_silae text, p_taux_horaire numeric, p_date_fin date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.creer_collaborateur_avec_contrat(p_collab_id text, p_token text, p_prenom text, p_nom text, p_nom_affiche text, p_email text, p_structure text, p_equipe_id text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_statut text, p_date_activation date, p_actif boolean, p_matricule_silae text, p_taux_horaire numeric, p_date_fin date) TO service_role;


--
-- Name: FUNCTION derniere_saisie_par_collab(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.derniere_saisie_par_collab() FROM PUBLIC;
GRANT ALL ON FUNCTION public.derniere_saisie_par_collab() TO anon;


--
-- Name: FUNCTION equipes_liste(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.equipes_liste() FROM PUBLIC;
GRANT ALL ON FUNCTION public.equipes_liste() TO service_role;


--
-- Name: FUNCTION evp_synthese(p_periode_id text, p_structure text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.evp_synthese(p_periode_id text, p_structure text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.evp_synthese(p_periode_id text, p_structure text) TO service_role;


--
-- Name: FUNCTION generer_jour_aujourdhui(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.generer_jour_aujourdhui() FROM PUBLIC;
GRANT ALL ON FUNCTION public.generer_jour_aujourdhui() TO service_role;


--
-- Name: FUNCTION generer_periodes_suivantes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.generer_periodes_suivantes() FROM PUBLIC;


--
-- Name: FUNCTION journal_archives(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.journal_archives() FROM PUBLIC;
GRANT ALL ON FUNCTION public.journal_archives() TO service_role;


--
-- Name: FUNCTION journal_cloturer(p_par text, p_contenu text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.journal_cloturer(p_par text, p_contenu text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.journal_cloturer(p_par text, p_contenu text) TO service_role;


--
-- Name: FUNCTION journal_mouvements(p_depuis timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.journal_mouvements(p_depuis timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.journal_mouvements(p_depuis timestamp with time zone) TO service_role;


--
-- Name: FUNCTION journal_tache_creer(p_objet text, p_tiers text, p_collab_id text, p_note text, p_date_echeance date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.journal_tache_creer(p_objet text, p_tiers text, p_collab_id text, p_note text, p_date_echeance date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.journal_tache_creer(p_objet text, p_tiers text, p_collab_id text, p_note text, p_date_echeance date) TO service_role;


--
-- Name: FUNCTION journal_tache_traiter(p_id bigint, p_statut text, p_fait_par text, p_remarque text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.journal_tache_traiter(p_id bigint, p_statut text, p_fait_par text, p_remarque text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.journal_tache_traiter(p_id bigint, p_statut text, p_fait_par text, p_remarque text) TO service_role;


--
-- Name: FUNCTION journal_taches_liste(p_statut text, p_mouvement text, p_type_contrat text, p_tiers text, p_structure text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.journal_taches_liste(p_statut text, p_mouvement text, p_type_contrat text, p_tiers text, p_structure text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.journal_taches_liste(p_statut text, p_mouvement text, p_type_contrat text, p_tiers text, p_structure text) TO service_role;


--
-- Name: FUNCTION manager_equipe(p_manager_token text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.manager_equipe(p_manager_token text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.manager_equipe(p_manager_token text) TO service_role;


--
-- Name: FUNCTION materialiser_journal_taches(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.materialiser_journal_taches() FROM PUBLIC;
GRANT ALL ON FUNCTION public.materialiser_journal_taches() TO service_role;


--
-- Name: FUNCTION modifier_contrat(p_id bigint, p_date_debut date, p_date_fin date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_modifie_par text, p_taux_horaire numeric, p_rupture_anticipee boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.modifier_contrat(p_id bigint, p_date_debut date, p_date_fin date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_modifie_par text, p_taux_horaire numeric, p_rupture_anticipee boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.modifier_contrat(p_id bigint, p_date_debut date, p_date_fin date, p_structure text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_matricule_silae text, p_modifie_par text, p_taux_horaire numeric, p_rupture_anticipee boolean) TO service_role;


--
-- Name: FUNCTION ouvrir_geler_periodes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ouvrir_geler_periodes() FROM PUBLIC;


--
-- Name: FUNCTION rafraichir_fiche_collab(p_collab_id text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rafraichir_fiche_collab(p_collab_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.rafraichir_fiche_collab(p_collab_id text) TO service_role;


--
-- Name: FUNCTION renouveler_contrats_lot(p_ids bigint[], p_date_debut date, p_date_fin date, p_par text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.renouveler_contrats_lot(p_ids bigint[], p_date_debut date, p_date_fin date, p_par text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.renouveler_contrats_lot(p_ids bigint[], p_date_debut date, p_date_fin date, p_par text) TO service_role;


--
-- Name: FUNCTION rls_auto_enable(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC;


--
-- Name: FUNCTION supprimer_contrat(p_id bigint); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.supprimer_contrat(p_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION public.supprimer_contrat(p_id bigint) TO service_role;


--
-- Name: FUNCTION synchroniser_activite(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.synchroniser_activite() FROM PUBLIC;
GRANT ALL ON FUNCTION public.synchroniser_activite() TO service_role;


--
-- Name: FUNCTION trigger_quotidien(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trigger_quotidien() FROM PUBLIC;


--
-- Name: FUNCTION verifier_admin(p_token text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.verifier_admin(p_token text) TO anon;


--
-- Name: TABLE admins; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,MAINTAIN ON TABLE public.admins TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.admins TO authenticated;
GRANT ALL ON TABLE public.admins TO service_role;


--
-- Name: TABLE equipes; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,MAINTAIN ON TABLE public.equipes TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.equipes TO authenticated;
GRANT ALL ON TABLE public.equipes TO service_role;


--
-- Name: TABLE journal_editions; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,MAINTAIN ON TABLE public.journal_editions TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.journal_editions TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.journal_editions TO service_role;


--
-- Name: TABLE journal_regles; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.journal_regles TO authenticated;
GRANT ALL ON TABLE public.journal_regles TO service_role;


--
-- Name: TABLE journal_taches; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.journal_taches TO authenticated;
GRANT ALL ON TABLE public.journal_taches TO service_role;


--
-- Name: TABLE jours; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE public.jours TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.jours TO authenticated;
GRANT ALL ON TABLE public.jours TO service_role;


--
-- Name: TABLE paie_detail; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE public.paie_detail TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.paie_detail TO authenticated;
GRANT ALL ON TABLE public.paie_detail TO service_role;


--
-- Name: TABLE periodes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE public.periodes TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.periodes TO authenticated;
GRANT ALL ON TABLE public.periodes TO service_role;


--
-- Name: TABLE recap_paie; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE public.recap_paie TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.recap_paie TO authenticated;
GRANT ALL ON TABLE public.recap_paie TO service_role;


--
-- Name: TABLE structures; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,MAINTAIN ON TABLE public.structures TO anon;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.structures TO authenticated;
GRANT ALL ON TABLE public.structures TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--


