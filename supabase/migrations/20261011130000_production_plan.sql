-- ============================================================================
-- Plan de culture maraîchère — 005 · Le plan
-- Cultures datées, affectations en mètres, occupations par planche.
-- ============================================================================

-- ============================================================================
-- Cultures
-- La culture datée : le prévu ET le réalisé, un statut au lieu d'une
-- suppression. Les semaines 00-52 de FileMaker deviennent de vraies dates,
-- et « cult sur 2 ans » disparaît : un poireau semé en mai et récolté en
-- février suivant est une culture ordinaire.
-- ============================================================================

create table production.culture (
  id                      uuid primary key default gen_random_uuid(),
  code                    text not null unique,
  campagne_id             uuid not null references production.campagne (id),
  legume_id               uuid not null references production.legume (id),
  itineraire_id           uuid references production.itineraire (id),
  contexte                production.contexte_production not null default 'plein_champ',
  numero_semis            smallint,
  groupe_assolement_id    uuid references production.groupe_assolement (id),
  fournisseur_plants_id   uuid references production.fournisseur (id),
  ordre_plantation        integer,
  est_engrais_vert        boolean not null default false,
  en_plein                boolean not null default false,

  quantite_prevue         numeric(12,3) check (quantite_prevue >= 0),
  unite_quantite          text references production.unite (code),

  date_semis_prevue       date,
  date_plantation_prevue  date,
  debut_recolte_prevu     date,
  fin_recolte_prevue      date,

  date_semis_reelle       date,
  date_plantation_reelle  date,
  debut_recolte_reel      date,
  fin_recolte_reelle      date,
  rendement_reel          numeric(12,3) check (rendement_reel >= 0),

  statut                  production.statut_culture not null default 'prevue',
  motif_annulation        text,
  date_decision           date,
  note                    text,

  constraint culture_annulation_motivee check (
    statut <> 'annulee' or motif_annulation is not null
  ),
  constraint culture_recolte_prevue_coherente check (
    fin_recolte_prevue is null or debut_recolte_prevu is null
    or fin_recolte_prevue >= debut_recolte_prevu
  ),
  constraint culture_recolte_reelle_coherente check (
    fin_recolte_reelle is null or debut_recolte_reel is null
    or fin_recolte_reelle >= debut_recolte_reel
  )
);

create index culture_campagne_idx  on production.culture (campagne_id);
create index culture_legume_idx    on production.culture (legume_id);
create index culture_statut_idx    on production.culture (statut);
create index culture_contexte_idx  on production.culture (campagne_id, contexte);

comment on column production.culture.statut is
  'Les fenouils de la semaine 14 qu''on ne fait plus ne sont pas supprimés : '
  'ils passent en annulée, avec un motif et une date. En janvier suivant, la '
  'décision est encore lisible.';

comment on column production.culture.en_plein is
  'Couvre toute la parcelle, passages de roue compris. Le cas des engrais '
  'verts : la surface se compte alors sur la parcelle entière, mais '
  'l''historique de chaque planche reste complet.';

comment on column production.culture.unite_quantite is
  'Planches en plein champ, plants ou caisses sous serre. Le besoin s''exprime '
  'dans l''unité qui arrange, pas dans une unité imposée.';


-- ============================================================================
-- Affectations
-- Grain : culture x variété x parcelle. Compte en mètres continus, ce qui
-- permet aux variétés de s'enchaîner sans laisser de vide entre elles.
-- ============================================================================

create table production.affectation (
  id                uuid primary key default gen_random_uuid(),
  code              text unique,
  culture_id        uuid not null references production.culture (id) on delete cascade,
  variete_id        uuid references production.variete (id),
  parcelle_id       uuid not null references production.parcelle (id),
  unite_debut_id    uuid references production.unite_culture (id),
  sens              production.sens_implantation not null default 'croissant',
  longueur_m        numeric(10,2) not null check (longueur_m > 0),
  ordre_plantation  integer,
  nb_caisses_force  integer check (nb_caisses_force >= 0),
  note              text
);

create index affectation_culture_idx  on production.affectation (culture_id);
create index affectation_parcelle_idx on production.affectation (parcelle_id);
create index affectation_variete_idx  on production.affectation (variete_id);

comment on column production.affectation.variete_id is
  'Facultatif. Vide, l''affectation porte la culture entière dans son '
  'mélange ; renseigné, elle précise. D''où la possibilité d''affecter d''un '
  'bloc, de scinder par variété, d''étaler sur deux parcelles, ou les trois.';

comment on column production.affectation.unite_debut_id is
  'Planche de départ. Avec le sens, elle rend la pose des mètres sur les '
  'planches déterministe : sans elle, rien ne dit où commencer 832 mètres '
  'dans une parcelle qui en compte vingt.';

comment on column production.affectation.nb_caisses_force is
  'Prend le pas sur le calcul. 1 200 plants à 264 la caisse font 4,54 '
  'caisses : c''est toi qui tranches, pas la machine.';


-- ============================================================================
-- Occupations
-- Grain : unité de culture x période. Ce qui occupe physiquement une planche,
-- culture ou non. Répond aux surfaces libres et à l'historique de rotation.
-- Générée depuis les affectations, corrigeable à la main.
-- ============================================================================

create table production.occupation (
  id                uuid primary key default gen_random_uuid(),
  unite_culture_id  uuid not null references production.unite_culture (id) on delete cascade,
  type              production.type_occupation not null,
  culture_id        uuid references production.culture (id) on delete cascade,
  equipement_id     uuid references production.equipement (id),
  periode           daterange not null,
  fraction_unite    numeric(5,4) not null default 1
                      check (fraction_unite > 0 and fraction_unite <= 1),
  en_plein          boolean not null default false,
  origine           production.origine_donnee not null default 'calculee',
  note              text,

  constraint occupation_culture_renseignee check (
    type not in ('culture', 'engrais_vert') or culture_id is not null
  ),
  constraint occupation_materiel_renseigne check (
    type <> 'materiel' or equipement_id is not null
  )
);

create index occupation_unite_idx    on production.occupation (unite_culture_id);
create index occupation_culture_idx  on production.occupation (culture_id);
create index occupation_periode_idx  on production.occupation
  using gist (unite_culture_id, periode);

comment on column production.occupation.origine is
  'Une occupation forcée n''est jamais écrasée par un recalcul. La planche '
  'sautée parce qu''elle était détrempée ne revient pas toute seule.';

comment on index production.occupation_periode_idx is
  'Index GiST : répond en une passe à « qu''est-ce qui chevauche la semaine '
  '30 ? ». Pas de contrainte d''exclusion volontairement — on alerte sur les '
  'chevauchements, on ne les interdit pas.';


-- ============================================================================
-- Calculs de l'affectation
-- Les formules croisent trois tables (itinéraire, parcelle, affectation) :
-- une colonne générée ne le permet pas, une vue si — et elle ne périme jamais.
-- Reprise exacte des formules FileMaker.
-- ============================================================================

create view production.v_affectation as
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
  i.nb_rangs_par_planche,
  i.espacement_sur_rang_cm,
  i.nb_par_caisse,

  a.longueur_m * p.largeur_planche_m                       as surface_occupee_m2,
  a.longueur_m * p.largeur_utile_m                         as surface_cultivee_m2,
  a.longueur_m * p.largeur_planche_m / 204                 as equivalent_120,

  case when i.espacement_sur_rang_cm > 0
       then floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
            * i.nb_rangs_par_planche
  end                                                      as nb_plants,

  case when i.espacement_sur_rang_cm > 0 and i.nb_par_caisse > 0
       then ceil(
              floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
              * i.nb_rangs_par_planche::numeric / i.nb_par_caisse
            )
  end                                                      as nb_caisses_calcule,

  coalesce(
    a.nb_caisses_force,
    case when i.espacement_sur_rang_cm > 0 and i.nb_par_caisse > 0
         then ceil(
                floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
                * i.nb_rangs_par_planche::numeric / i.nb_par_caisse
              )::integer
    end
  )                                                        as nb_caisses_retenu

from production.affectation a
join production.culture  c on c.id = a.culture_id
join production.parcelle p on p.id = a.parcelle_id
left join production.itineraire i on i.id = c.itineraire_id;

comment on view production.v_affectation is
  'Les figures de l''affectation : surfaces, plants, caisses. Toujours à '
  'jour — contrairement aux rubriques FileMaker qu''il fallait rafraîchir '
  'avec un bouton.';


-- ============================================================================
-- Journal d'audit
-- ============================================================================

create trigger culture_audit after insert or update or delete on production.culture
  for each row execute function production.tracer_historique();
create trigger affectation_audit after insert or update or delete on production.affectation
  for each row execute function production.tracer_historique();
create trigger occupation_audit after insert or update or delete on production.occupation
  for each row execute function production.tracer_historique();


-- ============================================================================
-- Droits
-- ============================================================================

alter table production.culture     enable row level security;
alter table production.affectation enable row level security;
alter table production.occupation  enable row level security;

create policy culture_lecture on production.culture
  for select to anon, authenticated using (true);
create policy affectation_lecture on production.affectation
  for select to anon, authenticated using (true);
create policy occupation_lecture on production.occupation
  for select to anon, authenticated using (true);

grant select on production.culture       to anon, authenticated;
grant select on production.affectation   to anon, authenticated;
grant select on production.occupation    to anon, authenticated;
grant select on production.v_affectation to anon, authenticated;

alter view production.v_affectation set (security_invoker = true);
