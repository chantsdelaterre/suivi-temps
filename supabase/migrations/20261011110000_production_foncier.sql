-- ============================================================================
-- Plan de culture maraîchère — 003 · Foncier et campagnes
-- Îlots, parcelles, et la planche comme objet à part entière.
-- Corrige au passage le droit de lecture accordé par défaut dans le socle.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Correction du socle.
-- Le fichier 001 accordait la lecture à anon sur toute table future du schéma.
-- Commode, mais ça redonne silencieusement l'accès à une table sensible dès
-- qu'on relance un grant global. Désormais chaque table reçoit ses droits
-- explicitement.
-- ----------------------------------------------------------------------------

alter default privileges in schema production
  revoke select on tables from anon, authenticated;

revoke select on production.tarif from anon;


create type production.type_parcelle as enum (
  'plein_champ', 'serre', 'tunnel'
);

create type production.statut_campagne as enum (
  'preparation', 'active', 'cloturee'
);


-- ============================================================================
-- Campagnes
-- Une étiquette qui sert à filtrer et à dupliquer, jamais une frontière :
-- une culture qui hiverne chevauche le 31 décembre sans cas particulier.
-- ============================================================================

create table production.campagne (
  id          uuid primary key default gen_random_uuid(),
  libelle     text not null unique,
  date_debut  date not null,
  date_fin    date not null,
  statut      production.statut_campagne not null default 'preparation',
  note        text,
  constraint campagne_dates_coherentes check (date_fin > date_debut)
);


-- ============================================================================
-- Îlots
-- ============================================================================

create table production.ilot (
  id                   uuid primary key default gen_random_uuid(),
  code                 text not null unique,
  nom                  text not null,
  ilot_pac             text,
  entite_juridique_id  uuid references production.entite_juridique (id),
  surface_cadastre_m2  numeric(12,2) check (surface_cadastre_m2 >= 0),
  plan_url             text,
  photo_url            text,
  note                 text,
  surface_cadastre_ha  numeric(12,4)
    generated always as (surface_cadastre_m2 / 10000) stored
);

create index ilot_entite_idx on production.ilot (entite_juridique_id);


-- ============================================================================
-- Parcelles
-- Une serre est une parcelle d'un autre type, pas un cas particulier.
-- ============================================================================

create table production.parcelle (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null unique,
  nom                text not null,
  ilot_id            uuid references production.ilot (id),
  type               production.type_parcelle not null default 'plein_champ',
  largeur_planche_m  numeric(6,3) not null default 1.700 check (largeur_planche_m > 0),
  largeur_utile_m    numeric(6,3) not null default 1.400 check (largeur_utile_m > 0),
  plan_url           text,
  photo_url          text,
  actif              boolean not null default true,
  note               text,
  constraint parcelle_largeurs_coherentes check (largeur_utile_m <= largeur_planche_m)
);

create index parcelle_ilot_idx on production.parcelle (ilot_id);

comment on column production.parcelle.largeur_planche_m is
  'Emprise d''une planche, passage de roue compris : 1,70 m en plein champ. '
  'Sert aux surfaces et à l''assolement.';

comment on column production.parcelle.largeur_utile_m is
  'Bande réellement cultivée : 1,40 m en plein champ, les 30 cm restants '
  'étant le passage de roue. Sert aux densités et aux rendements.';


-- ============================================================================
-- Unités de culture — la planche comme objet
-- Environ 1 500 lignes. Chacune porte sa longueur, ce qui rend calculable
-- l'écart entre plants commandés et longueur réellement disponible.
-- Les planches sont orientées nord-sud : l'axe vertical est la longueur,
-- l'axe horizontal la largeur de la parcelle.
-- ============================================================================

create table production.unite_culture (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null,
  parcelle_id        uuid not null references production.parcelle (id) on delete cascade,
  unite_parente_id   uuid references production.unite_culture (id) on delete cascade,
  ordre              integer not null,
  x_debut_m          numeric(8,2) not null check (x_debut_m >= 0),
  longueur_m         numeric(8,2) not null check (longueur_m > 0),
  largeur_m          numeric(6,3) not null check (largeur_m > 0),
  largeur_utile_m    numeric(6,3) not null check (largeur_utile_m > 0),
  permanente         boolean not null default true,
  campagne_id        uuid references production.campagne (id),
  actif              boolean not null default true,
  note               text,

  surface_occupee_m2  numeric(14,3)
    generated always as (longueur_m * largeur_m) stored,
  surface_cultivee_m2 numeric(14,3)
    generated always as (longueur_m * largeur_utile_m) stored,
  equivalent_120      numeric(12,4)
    generated always as (longueur_m * largeur_m / 204) stored,

  unique (parcelle_id, code),
  constraint unite_largeurs_coherentes check (largeur_utile_m <= largeur_m),
  constraint unite_temporaire_a_une_campagne check (
    permanente or campagne_id is not null
  )
);

create index unite_parcelle_idx on production.unite_culture (parcelle_id, ordre);
create index unite_parente_idx  on production.unite_culture (unite_parente_id);
create index unite_campagne_idx on production.unite_culture (campagne_id);

comment on column production.unite_culture.x_debut_m is
  'Position de la planche sur l''axe est-ouest de la parcelle, en mètres. '
  'C''est ce qui permet de travailler en emprise métrique — une bande de '
  '35 m au déchaumeur ignore les limites de planches.';

comment on column production.unite_culture.ordre is
  'Rang de la planche dans la parcelle, d''ouest en est. Porte la '
  'représentation : des planches côte à côte, vues du dessus.';

comment on column production.unite_culture.unite_parente_id is
  'Sous serre, les lignes de salade sont des unités filles rattachées à une '
  'campagne et refaites chaque année. En plein champ, les planches sont '
  'permanentes.';

comment on column production.unite_culture.equivalent_120 is
  'Surface rapportée à la planche de référence de 120 m sur 1,70, soit '
  '204 m². La monnaie de compte : trois planches de chou-rave l''an dernier, '
  'quatre cette année.';


-- ============================================================================
-- Journal d'audit
-- ============================================================================

create trigger campagne_audit after insert or update or delete on production.campagne
  for each row execute function production.tracer_historique();
create trigger ilot_audit after insert or update or delete on production.ilot
  for each row execute function production.tracer_historique();
create trigger parcelle_audit after insert or update or delete on production.parcelle
  for each row execute function production.tracer_historique();
create trigger unite_culture_audit after insert or update or delete on production.unite_culture
  for each row execute function production.tracer_historique();


-- ============================================================================
-- Droits, accordés table par table
-- ============================================================================

alter table production.campagne      enable row level security;
alter table production.ilot          enable row level security;
alter table production.parcelle      enable row level security;
alter table production.unite_culture enable row level security;

create policy campagne_lecture on production.campagne
  for select to anon, authenticated using (true);
create policy ilot_lecture on production.ilot
  for select to anon, authenticated using (true);
create policy parcelle_lecture on production.parcelle
  for select to anon, authenticated using (true);
create policy unite_culture_lecture on production.unite_culture
  for select to anon, authenticated using (true);

grant select on production.campagne      to anon, authenticated;
grant select on production.ilot          to anon, authenticated;
grant select on production.parcelle      to anon, authenticated;
grant select on production.unite_culture to anon, authenticated;
