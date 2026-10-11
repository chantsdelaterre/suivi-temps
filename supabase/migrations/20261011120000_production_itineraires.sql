-- ============================================================================
-- Plan de culture maraîchère — 004 · Itinéraires et équipements
-- La recette d'une culture, indépendamment de toute date.
-- ============================================================================

create type production.mode_implantation as enum (
  'semis_direct', 'plant'
);

create type production.categorie_equipement as enum (
  'irrigation', 'protection', 'autre'
);

create type production.reference_decalage as enum (
  'semis', 'plantation', 'debut_recolte'
);


-- ============================================================================
-- Équipements
-- Le catalogue et surtout la quantité possédée : si le plan réclame
-- 3,2 ha de couverture intégrale en semaine 14 et qu'on en a 2,5, le
-- conflit existe dans le plan bien avant d'exister au champ.
-- ============================================================================

create table production.equipement (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null unique,
  nom                   text not null,
  categorie             production.categorie_equipement not null,
  quantite_disponible   numeric(12,2) check (quantite_disponible >= 0),
  unite                 text references production.unite (code),
  reutilisable          boolean not null default true,
  duree_vie_campagnes   smallint check (duree_vie_campagnes > 0),
  actif                 boolean not null default true,
  note                  text
);

comment on table production.equipement is
  'Couverture intégrale, enrouleur, goutte-à-goutte, P17, voile '
  'anti-insectes. La quantité possédée est ce qui rend la planification '
  'possible.';


-- ============================================================================
-- Itinéraires techniques
-- ============================================================================

create table production.itineraire (
  id                        uuid primary key default gen_random_uuid(),
  code                      text not null unique,
  nom                       text not null,
  legume_id                 uuid not null references production.legume (id),
  contexte                  production.contexte_production not null default 'plein_champ',
  mode_implantation         production.mode_implantation not null,

  nb_rangs_par_planche      smallint check (nb_rangs_par_planche > 0),
  espacement_entre_rangs_cm numeric(7,2) check (espacement_entre_rangs_cm > 0),
  espacement_sur_rang_cm    numeric(7,2) check (espacement_sur_rang_cm > 0),

  duree_pepiniere_jours     smallint check (duree_pepiniere_jours >= 0),
  duree_en_place_jours      smallint check (duree_en_place_jours >= 0),
  duree_recolte_jours       smallint check (duree_recolte_jours >= 0),

  materiel_vegetal_id       uuid references production.materiel_vegetal (id),
  materiel_id               uuid references production.materiel (id),
  nb_par_caisse             integer check (nb_par_caisse > 0),

  rendement_attendu         numeric(12,3) check (rendement_attendu >= 0),
  unite_rendement           text references production.unite (code),

  fixation                  text,
  actif                     boolean not null default true,
  note                      text,

  emprise_rangs_cm numeric(9,2)
    generated always as (
      (nb_rangs_par_planche - 1) * espacement_entre_rangs_cm
    ) stored,

  densite_theorique_m2 numeric(10,3)
    generated always as (
      case
        when espacement_entre_rangs_cm > 0 and espacement_sur_rang_cm > 0
        then 10000 / (espacement_entre_rangs_cm * espacement_sur_rang_cm)
      end
    ) stored
);

create index itineraire_legume_idx   on production.itineraire (legume_id);
create index itineraire_contexte_idx on production.itineraire (contexte);

comment on column production.itineraire.espacement_entre_rangs_cm is
  'Distance entre deux rangs voisins, dans la largeur de la planche. '
  'Saisie, jamais déduite du nombre de rangs.';

comment on column production.itineraire.espacement_sur_rang_cm is
  'Distance entre deux plants sur le rang, dans la longueur.';

comment on column production.itineraire.emprise_rangs_cm is
  'Largeur occupée par les rangs : quatre rangs à 30 cm font 90 cm. '
  'Doit tenir dans la largeur utile de la parcelle — 140 cm en plein champ. '
  'Six rangs à 30 cm feraient 150 cm : impossible, et l''outil le dira à la '
  'saisie.';

comment on column production.itineraire.densite_theorique_m2 is
  'Plants au mètre carré, produit inverse des deux écartements : 30 x 30 '
  'donne 11,11. C''est le chiffre comparable à la littérature agronomique, '
  'indépendant de la largeur de planche.';

comment on column production.itineraire.contexte is
  'Plein champ ou serre. Une salade sous serre et une salade de plein champ '
  'n''ont ni les mêmes densités ni les mêmes durées : ce sont deux '
  'itinéraires distincts.';


-- ============================================================================
-- Équipements réclamés par un itinéraire
-- Pose et dépose datées, comme les façons culturales.
-- ============================================================================

create table production.itineraire_equipement (
  id                     uuid primary key default gen_random_uuid(),
  itineraire_id          uuid not null references production.itineraire (id) on delete cascade,
  equipement_id          uuid not null references production.equipement (id),
  reference              production.reference_decalage not null default 'plantation',
  decalage_pose_jours    smallint not null default 0,
  decalage_depose_jours  smallint,
  obligatoire            boolean not null default true,
  note                   text,
  unique (itineraire_id, equipement_id),
  constraint depose_apres_pose check (
    decalage_depose_jours is null or decalage_depose_jours >= decalage_pose_jours
  )
);

create index itineraire_equipement_equip_idx
  on production.itineraire_equipement (equipement_id);

comment on column production.itineraire_equipement.reference is
  'Point d''ancrage du décalage. Sans lui, « J+30 » ne veut rien dire dès '
  'qu''une plantation glisse.';


-- ============================================================================
-- Équipements installés sur une parcelle
-- La table des impossibilités : une parcelle sans accès à l'eau ne peut pas
-- accueillir une culture qui en exige.
-- ============================================================================

create table production.parcelle_equipement (
  id                 uuid primary key default gen_random_uuid(),
  parcelle_id        uuid not null references production.parcelle (id) on delete cascade,
  equipement_id      uuid not null references production.equipement (id),
  permanent          boolean not null default true,
  date_installation  date,
  note               text,
  unique (parcelle_id, equipement_id)
);

create index parcelle_equipement_equip_idx
  on production.parcelle_equipement (equipement_id);


-- ============================================================================
-- Journal d'audit
-- ============================================================================

create trigger equipement_audit after insert or update or delete on production.equipement
  for each row execute function production.tracer_historique();
create trigger itineraire_audit after insert or update or delete on production.itineraire
  for each row execute function production.tracer_historique();
create trigger itineraire_equipement_audit after insert or update or delete on production.itineraire_equipement
  for each row execute function production.tracer_historique();
create trigger parcelle_equipement_audit after insert or update or delete on production.parcelle_equipement
  for each row execute function production.tracer_historique();


-- ============================================================================
-- Droits
-- ============================================================================

alter table production.equipement            enable row level security;
alter table production.itineraire            enable row level security;
alter table production.itineraire_equipement enable row level security;
alter table production.parcelle_equipement   enable row level security;

create policy equipement_lecture on production.equipement
  for select to anon, authenticated using (true);
create policy itineraire_lecture on production.itineraire
  for select to anon, authenticated using (true);
create policy itineraire_equipement_lecture on production.itineraire_equipement
  for select to anon, authenticated using (true);
create policy parcelle_equipement_lecture on production.parcelle_equipement
  for select to anon, authenticated using (true);

grant select on production.equipement            to anon, authenticated;
grant select on production.itineraire            to anon, authenticated;
grant select on production.itineraire_equipement to anon, authenticated;
grant select on production.parcelle_equipement   to anon, authenticated;
