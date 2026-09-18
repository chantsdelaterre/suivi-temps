-- =============================================================================
-- journal_mouvements.sql
-- Date       : 2026-09-18
-- But        : Alimente le Journal des déclarations (appli → journal → MSA/Silae).
--              Renvoie, depuis la dernière clôture (borne = max(edite_le)) :
--                • 'creation'     — contrat écrit après la borne (created_at) ;
--                • 'modification' — contrat modifié après la borne (modifie_le) ;
--                • 'fin'          — contrat dont date_fin est PASSÉE (strictement,
--                                   une fin au 30/09 sort le 01/10 : « on termine
--                                   le contrat, ensuite l'administratif ») ET
--                                   postérieure à la borne. Exclut les ruptures ;
--                • 'rupture'      — idem 'fin' mais rupture_anticipee = true.
--              'fin' et 'rupture' NE SONT PAS des écritures : elles surviennent
--              par le calendrier. La 2ᵉ condition (date_fin > borne::date) est
--              essentielle : sans elle les mêmes fins ressortiraient à chaque
--              ouverture du journal. Un contrat peut légitimement sortir deux fois
--              (créé après la borne ET fini après la borne) : deux démarches.
--              cree = false pour 'fin' et 'rupture'.
--              Consommée par l'Edge « journal » (action=mouvements) puis par
--              rendreHtmlJournal / composerTexteJournal (admin-v2.html).
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Droits      : STABLE SECURITY DEFINER. Appelée par l'Edge « journal » en
--              service_role après vérification du token admin (verifier_admin).
-- ⚠️ Colonnes/ordre de sortie FIGÉS : le front lit les noms de colonnes tels
--    quels. Ne changer NI la signature NI le nom des colonnes sans adapter
--    l'Edge journal ET les deux fonctions de rendu.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.journal_mouvements()
 RETURNS TABLE(structure text, destination text, collab_id text, nom_complet text, matricule_silae text, contrat_id bigint, mouvement text, date_debut date, date_fin date, heures_hebdo numeric, taux_horaire numeric, type_contrat text, rupture_anticipee boolean, cree boolean, borne timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with borne as (
    select coalesce(max(edite_le), '2000-01-01'::timestamptz) as depuis
    from journal_editions
  )
  select
    x.structure, x.destination, x.collab_id, x.nom_complet, x.matricule_silae,
    x.contrat_id, x.mouvement, x.date_debut, x.date_fin, x.heures_hebdo,
    x.taux_horaire, x.type_contrat, x.rupture_anticipee, x.cree, x.borne
  from (

    -- 1) EXISTANT : écritures (création / modification) depuis la borne.
    select
      h.structure                                              as structure,
      case when h.type_contrat = 'TESA' then 'MSA' else 'SILAE' end as destination,
      h.collab_id                                              as collab_id,
      coalesce(c.nom_affiche, c.prenom || ' ' || c.nom)        as nom_complet,
      case when h.type_contrat = 'TESA' then null else c.matricule_silae end as matricule_silae,
      h.id                                                     as contrat_id,
      case when h.created_at > b.depuis then 'creation' else 'modification' end as mouvement,
      h.date_debut, h.date_fin, h.heures_hebdo, h.taux_horaire,
      h.type_contrat, h.rupture_anticipee,
      (h.created_at > b.depuis)                                as cree,
      b.depuis                                                 as borne,
      coalesce(c.nom_affiche, c.nom)                           as tri_nom
    from historique_contrats h
    join collaborateurs c on c.collab_id = h.collab_id
    cross join borne b
    where h.created_at > b.depuis
       or (h.modifie_le is not null and h.modifie_le > b.depuis)

    union all

    -- 2) fins de contrat (calendaires, pas des écritures).
    --    date_fin STRICTEMENT passée (une fin au 30/09 sort le 01/10) ET postérieure
    --    à la dernière clôture. Exclut les ruptures.
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
      coalesce(c.nom_affiche, c.nom)
    from historique_contrats h
    join collaborateurs c on c.collab_id = h.collab_id
    cross join borne b
    where h.date_fin is not null
      and h.date_fin < (now() at time zone 'Europe/Paris')::date
      and h.date_fin > b.depuis::date
      and coalesce(h.rupture_anticipee, false) = false

    union all

    -- 3) ruptures anticipées. Mêmes conditions, mais rupture_anticipee = true.
    --    Une rupture sort en 'rupture', jamais en 'fin'.
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
      coalesce(c.nom_affiche, c.nom)
    from historique_contrats h
    join collaborateurs c on c.collab_id = h.collab_id
    cross join borne b
    where h.date_fin is not null
      and h.date_fin < (now() at time zone 'Europe/Paris')::date
      and h.date_fin > b.depuis::date
      and h.rupture_anticipee = true

  ) x
  order by x.structure, x.destination, x.tri_nom, x.date_debut;
$function$
