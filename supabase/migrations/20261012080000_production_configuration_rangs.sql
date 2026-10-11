-- ============================================================================
-- Plan de culture maraîchère — 013 · Configuration de rangs et graines par motte
--
-- Deux manques révélés par l'import FileMaker :
--   1. L'écartement entre rangs n'est pas une valeur libre : c'est un réglage
--      de machine. Quatre rangs à 30 cm, c'est la planteuse ; douze rangs,
--      c'est le semoir à radis. Il passe donc en table.
--   2. Une motte peut contenir plusieurs graines — oignon, betterave — et la
--      densité réelle en dépend.
-- ============================================================================

-- ============================================================================
-- Configurations de rangs
-- ============================================================================

create table production.configuration_rangs (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,
  nom            text not null,
  nb_rangs       smallint not null check (nb_rangs > 0),
  ecartement_cm  numeric(7,2) not null check (ecartement_cm > 0),
  materiel_id    uuid references production.materiel (id),
  actif          boolean not null default true,
  note           text,
  emprise_cm numeric(9,2)
    generated always as ((nb_rangs - 1) * ecartement_cm) stored
);

create index configuration_rangs_materiel_idx
  on production.configuration_rangs (materiel_id);

comment on table production.configuration_rangs is
  'Le réglage des rangs sur une planche. Reprend la table de correspondance '
  'de FileMaker, qui déduisait l''écartement du nombre de rangs — sauf '
  'qu''elle est maintenant modifiable sans toucher au code.';

comment on column production.configuration_rangs.emprise_cm is
  'Largeur occupée par les rangs. Trois rangs à 45 et quatre rangs à 30 font '
  'tous deux 90 cm : ce n''est pas une division de la planche, c''est une '
  'largeur de travail constante.';

insert into production.configuration_rangs (code, nom, nb_rangs, ecartement_cm, note) values
  ('R1',  '1 rang',   1, 170, 'Reprise de la correspondance FileMaker'),
  ('R2',  '2 rangs',  2,  85, 'Reprise de la correspondance FileMaker'),
  ('R3',  '3 rangs',  3,  45, 'Reprise de la correspondance FileMaker'),
  ('R4',  '4 rangs',  4,  30, 'Reprise de la correspondance FileMaker'),
  ('R12', '12 rangs — semoir à radis', 12, 10,
   'Six éléments semeurs à double soc, douze lignes réparties sur 120 cm. '
   'Les 10 cm sont une moyenne : les socs allant par paires, le pas réel '
   'alterne.');


-- ============================================================================
-- Itinéraire : nouvelles colonnes
-- ============================================================================

alter table production.itineraire
  add column configuration_rangs_id uuid references production.configuration_rangs (id),
  add column graines_par_motte smallint not null default 1 check (graines_par_motte > 0);

create index itineraire_configuration_idx
  on production.itineraire (configuration_rangs_id);

comment on column production.itineraire.graines_par_motte is
  'Nombre de graines par motte. Supérieur à 1 pour les semis multiples — '
  'oignon, betterave. Distingue le nombre de mottes commandées du nombre de '
  'plants réellement en terre.';

comment on column production.itineraire.espacement_sur_rang_cm is
  'Distance entre deux plants sur le rang. Reste ici parce qu''elle est '
  'agronomique : 30 cm pour une salade, 12 pour un oignon. L''écartement '
  'entre rangs, lui, est mécanique et vit dans configuration_rangs.';


-- ============================================================================
-- v_affectation : source le nombre de rangs depuis la configuration,
-- et ajoute le nombre de graines.
-- Remplacement, pas suppression : v_preaffectation_solde et v_besoin_plants
-- en dépendent.
-- ============================================================================

create or replace view production.v_affectation as
select
  a.id,
  a.code,
  a.culture_id,
  a.variete_id,
  a.parcelle_id,
  a.unite_debut_id,
  a.sens,
  a.longueur_m,
  a.ordre_plantation,
  a.nb_caisses_force,

  c.campagne_id,
  c.statut,
  i.id                        as itineraire_id,
  cr.nb_rangs                 as nb_rangs_par_planche,
  i.espacement_sur_rang_cm,
  i.nb_par_caisse,

  a.longueur_m * p.largeur_planche_m                       as surface_occupee_m2,
  a.longueur_m * p.largeur_utile_m                         as surface_cultivee_m2,
  a.longueur_m * p.largeur_planche_m / 204                 as equivalent_120,

  case when i.espacement_sur_rang_cm > 0
       then floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
            * cr.nb_rangs
  end                                                      as nb_plants,

  case when i.espacement_sur_rang_cm > 0 and i.nb_par_caisse > 0
       then ceil(
              floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
              * cr.nb_rangs::numeric / i.nb_par_caisse
            )
  end                                                      as nb_caisses_calcule,

  coalesce(
    a.nb_caisses_force,
    case when i.espacement_sur_rang_cm > 0 and i.nb_par_caisse > 0
         then ceil(
                floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
                * cr.nb_rangs::numeric / i.nb_par_caisse
              )::integer
    end
  )                                                        as nb_caisses_retenu,

  -- Ajout : les graines réellement semées, quand une motte en contient
  -- plusieurs. nb_plants compte les mottes, c'est-à-dire ce qui se commande.
  case when i.espacement_sur_rang_cm > 0
       then floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
            * cr.nb_rangs * i.graines_par_motte
  end                                                      as nb_graines

from production.affectation a
join production.culture  c on c.id = a.culture_id
join production.parcelle p on p.id = a.parcelle_id
left join production.itineraire i on i.id = c.itineraire_id
left join production.configuration_rangs cr on cr.id = i.configuration_rangs_id;

-- Reposé explicitement : create or replace view sans clause WITH réinitialise
-- les options de la vue, donc security_invoker serait perdu. v_affectation est
-- accordée à anon : sans cette option elle s'exécuterait avec les droits de son
-- propriétaire et contournerait le RLS de l'appelant.
alter view production.v_affectation set (security_invoker = true);


-- ============================================================================
-- Retrait des colonnes remplacées
-- ============================================================================

alter table production.itineraire
  drop column emprise_rangs_cm,
  drop column densite_theorique_m2,
  drop column nb_rangs_par_planche,
  drop column espacement_entre_rangs_cm;

-- La machine ne porte plus son nombre de rangs : ce sont ses configurations
-- qui le portent, et elles renvoient à elle. La largeur de travail, en
-- revanche, reste sur la machine — c'est la largeur d'un passage au champ,
-- pas un réglage de rangs sur une planche.
alter table production.materiel
  drop column nb_rangs;


-- ============================================================================
-- v_itineraire : l'emprise et la densité, désormais calculées sur deux tables
-- ============================================================================

create view production.v_itineraire as
select
  i.id,
  i.code,
  i.nom,
  i.legume_id,
  i.contexte,
  i.mode_implantation,
  i.configuration_rangs_id,
  cr.code                     as configuration_code,
  cr.nb_rangs,
  cr.ecartement_cm            as espacement_entre_rangs_cm,
  cr.emprise_cm               as emprise_rangs_cm,
  i.espacement_sur_rang_cm,
  i.graines_par_motte,
  i.duree_pepiniere_jours,
  i.duree_en_place_jours,
  i.duree_recolte_jours,
  i.materiel_vegetal_id,
  i.materiel_id,
  i.nb_par_caisse,
  i.rendement_attendu,
  i.unite_rendement,
  i.actif,

  case when cr.ecartement_cm > 0 and i.espacement_sur_rang_cm > 0
       then 10000 * i.graines_par_motte
            / (cr.ecartement_cm * i.espacement_sur_rang_cm)
  end                         as densite_theorique_m2

from production.itineraire i
left join production.configuration_rangs cr on cr.id = i.configuration_rangs_id;

comment on view production.v_itineraire is
  'La densité théorique reprend la formule FileMaker : '
  '10000 x graines par motte / (écartement entre rangs x espacement sur '
  'rang). Quatre rangs à 30 cm, plants tous les 30 cm, une graine par motte : '
  '11,11 plants au mètre carré.';


-- ============================================================================
-- Journal d'audit et droits
-- ============================================================================

create trigger configuration_rangs_audit
  after insert or update or delete on production.configuration_rangs
  for each row execute function production.tracer_historique();

alter table production.configuration_rangs enable row level security;

create policy configuration_rangs_lecture on production.configuration_rangs
  for select to anon, authenticated using (true);

grant select on production.configuration_rangs to anon, authenticated;
grant select on production.v_itineraire        to anon, authenticated;

alter view production.v_itineraire set (security_invoker = true);
