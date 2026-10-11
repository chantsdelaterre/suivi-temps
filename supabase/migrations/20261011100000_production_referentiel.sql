-- ============================================================================
-- Plan de culture maraîchère — 002 · Référentiel
-- Familles botaniques, légumes, variétés, fournisseurs, matériel, tarifs.
-- Tout ce qui ne dépend ni d'une campagne ni d'une parcelle.
-- ============================================================================

create type production.nature_materiel_vegetal as enum (
  'motte', 'graine', 'tubercule', 'racine_nue', 'autre'
);

create type production.type_materiel as enum (
  'planteuse', 'semoir', 'epandeur', 'dechaumeur', 'pulverisateur',
  'butteuse', 'bineuse', 'autre'
);


-- ============================================================================
-- Familles et groupes
-- ============================================================================

create table production.famille_botanique (
  id                   uuid primary key default gen_random_uuid(),
  code                 text not null unique,
  nom                  text not null,
  delai_retour_annees  smallint check (delai_retour_annees >= 0),
  note                 text
);

comment on column production.famille_botanique.delai_retour_annees is
  'Nombre d''années avant de pouvoir remettre cette famille sur une planche. '
  'Ce qui rend la rotation contrôlable au lieu de reposer sur la mémoire.';

create table production.groupe_assolement (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  nom_court    text not null,
  description  text
);


-- ============================================================================
-- Fournisseurs
-- Semenciers et producteurs de plants dans une seule table, distingués par
-- leur rôle, ce qui permet de grouper les commandes.
-- ============================================================================

create table production.fournisseur (
  id                     uuid primary key default gen_random_uuid(),
  code                   text not null unique,
  nom                    text not null,
  est_semencier          boolean not null default false,
  est_plantier           boolean not null default false,
  pays                   text,
  langue                 text not null default 'fr',
  contact                text,
  delai_livraison_jours  smallint check (delai_livraison_jours >= 0),
  minimum_commande       numeric(12,2),
  actif                  boolean not null default true,
  note                   text
);

comment on column production.fournisseur.langue is
  'Langue des bons de commande adressés à ce fournisseur. Natterer : de.';


-- ============================================================================
-- Matériel
-- ============================================================================

create table production.materiel_vegetal (
  id            uuid primary key default gen_random_uuid(),
  nom           text not null unique,
  nature        production.nature_materiel_vegetal not null,
  nb_par_caisse integer check (nb_par_caisse > 0),
  note          text
);

comment on table production.materiel_vegetal is
  'La forme sous laquelle arrive ce qu''on implante : motte de 4, graine, '
  'tubercule. Détermine le conditionnement des caisses.';

create table production.materiel (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  nom               text not null,
  type              production.type_materiel not null,
  largeur_travail_m numeric(6,2) check (largeur_travail_m > 0),
  debit_horaire     numeric(12,2) check (debit_horaire > 0),
  unite_debit       text references production.unite (code),
  nb_rangs          smallint check (nb_rangs > 0),
  actif             boolean not null default true,
  note              text
);

comment on table production.materiel is
  'Les machines : planteuses, semoirs, épandeurs, déchaumeurs. AXIS, '
  'Terradisc, Fastblock, F-Max, Hortus.';

comment on column production.materiel.largeur_travail_m is
  'Largeur d''un passage. Permet de proposer une emprise en nombre entier '
  'de passages : un Terradisc de 6 m transforme 35 m demandés en 36 m.';


-- ============================================================================
-- Légumes et variétés
-- ============================================================================

create table production.legume (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null unique,
  nom                   text not null,
  nom_allemand          text,
  famille_botanique_id  uuid references production.famille_botanique (id),
  est_engrais_vert      boolean not null default false,
  actif                 boolean not null default true,
  note                  text
);

create index legume_famille_idx on production.legume (famille_botanique_id);

comment on column production.legume.est_engrais_vert is
  'Les engrais verts sont des légumes comme les autres : même mécanique de '
  'culture, mêmes commandes de semences.';

create table production.type_legume (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  nom        text not null,
  legume_id  uuid references production.legume (id)
);

create index type_legume_legume_idx on production.type_legume (legume_id);

create table production.variete (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null unique,
  nom                text not null,
  legume_id          uuid not null references production.legume (id),
  type_legume_id     uuid references production.type_legume (id),
  fournisseur_id     uuid references production.fournisseur (id),
  unite_vente        text references production.unite (code),
  base               numeric(12,3),
  pmg                numeric(10,3) check (pmg > 0),
  pmg_mis_a_jour_le  timestamptz,
  actif              boolean not null default true,
  note               text,
  graines_par_gramme numeric(14,3)
    generated always as (case when pmg > 0 then 1000 / pmg end) stored
);

create index variete_legume_idx      on production.variete (legume_id);
create index variete_fournisseur_idx on production.variete (fournisseur_id);

comment on column production.variete.pmg is
  'Poids de mille grains. Valeur courante, saisie une fois et corrigée quand '
  'elle bouge. Son historique vient du journal d''audit, pas d''une table '
  'par campagne.';

comment on column production.variete.pmg_mis_a_jour_le is
  'Posée automatiquement. Ne se saisit jamais.';


-- ============================================================================
-- Tarifs
-- Le prix d'achat courant ET le vocabulaire du fournisseur.
-- ============================================================================

create table production.tarif (
  id                      uuid primary key default gen_random_uuid(),
  variete_id              uuid not null references production.variete (id) on delete cascade,
  materiel_vegetal_id     uuid references production.materiel_vegetal (id),
  fournisseur_id          uuid not null references production.fournisseur (id),
  prix_achat              numeric(12,4) check (prix_achat >= 0),
  unite_prix              text references production.unite (code),
  conditionnement         numeric(12,3),
  reference_fournisseur   text,
  designation_fournisseur text,
  langue                  text,
  mis_a_jour_le           timestamptz,
  note                    text,
  unique (variete_id, materiel_vegetal_id, fournisseur_id)
);

create index tarif_fournisseur_idx on production.tarif (fournisseur_id);

comment on column production.tarif.designation_fournisseur is
  'Le libellé tel que le fournisseur l''écrit, dans sa langue. Saisi une '
  'fois, il sert à écrire les bons de commande sans traduction automatique, '
  'et plus tard à rapprocher les lignes d''une facture numérisée.';

comment on column production.tarif.prix_achat is
  'Prix facturé par le fournisseur. Sert à valoriser le stock. Le prix '
  'réellement payé sur une commande donnée est figé dans commande_ligne.';


-- ============================================================================
-- Horodatage automatique
-- ============================================================================

create trigger variete_pmg_horodate
  before insert or update on production.variete
  for each row execute function production.horodater_si_change('pmg', 'pmg_mis_a_jour_le');

create trigger tarif_prix_horodate
  before insert or update on production.tarif
  for each row execute function production.horodater_si_change('prix_achat', 'mis_a_jour_le');


-- ============================================================================
-- Journal d'audit
-- ============================================================================

create trigger famille_botanique_audit after insert or update or delete on production.famille_botanique
  for each row execute function production.tracer_historique();
create trigger groupe_assolement_audit after insert or update or delete on production.groupe_assolement
  for each row execute function production.tracer_historique();
create trigger fournisseur_audit after insert or update or delete on production.fournisseur
  for each row execute function production.tracer_historique();
create trigger materiel_vegetal_audit after insert or update or delete on production.materiel_vegetal
  for each row execute function production.tracer_historique();
create trigger materiel_audit after insert or update or delete on production.materiel
  for each row execute function production.tracer_historique();
create trigger legume_audit after insert or update or delete on production.legume
  for each row execute function production.tracer_historique();
create trigger type_legume_audit after insert or update or delete on production.type_legume
  for each row execute function production.tracer_historique();
create trigger variete_audit after insert or update or delete on production.variete
  for each row execute function production.tracer_historique();
create trigger tarif_audit after insert or update or delete on production.tarif
  for each row execute function production.tracer_historique();


-- ============================================================================
-- Droits : lecture pour le client, écriture par Edge Function uniquement
-- ============================================================================

alter table production.famille_botanique enable row level security;
alter table production.groupe_assolement enable row level security;
alter table production.fournisseur       enable row level security;
alter table production.materiel_vegetal  enable row level security;
alter table production.materiel          enable row level security;
alter table production.legume            enable row level security;
alter table production.type_legume       enable row level security;
alter table production.variete           enable row level security;
alter table production.tarif             enable row level security;

create policy famille_botanique_lecture on production.famille_botanique
  for select to anon, authenticated using (true);
create policy groupe_assolement_lecture on production.groupe_assolement
  for select to anon, authenticated using (true);
create policy fournisseur_lecture on production.fournisseur
  for select to anon, authenticated using (true);
create policy materiel_vegetal_lecture on production.materiel_vegetal
  for select to anon, authenticated using (true);
create policy materiel_lecture on production.materiel
  for select to anon, authenticated using (true);
create policy legume_lecture on production.legume
  for select to anon, authenticated using (true);
create policy type_legume_lecture on production.type_legume
  for select to anon, authenticated using (true);
create policy variete_lecture on production.variete
  for select to anon, authenticated using (true);

-- Les tarifs portent des prix d'achat : lecture réservée aux comptes
-- authentifiés, pas au rôle anonyme.
create policy tarif_lecture on production.tarif
  for select to authenticated using (true);

grant select on all tables in schema production to anon, authenticated;
revoke select on production.tarif from anon;
