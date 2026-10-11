-- ============================================================================
-- Plan de culture maraîchère — 001 · Socle
-- Schéma, types énumérés, unités, entités juridiques, journal d'audit.
-- N'altère rien du schéma public existant.
-- ============================================================================

create schema if not exists production;

-- btree_gist est nécessaire plus tard pour les contraintes d'exclusion
-- sur les périodes d'occupation (une planche, deux cultures qui se chevauchent).
create extension if not exists btree_gist with schema extensions;


-- ============================================================================
-- Types énumérés
-- Réservés aux listes réellement closes : y ajouter une valeur doit être une
-- décision, pas une commodité. Tout ce qui vit (unités, façons culturales,
-- équipements) est en table.
-- ============================================================================

create type production.dimension_unite as enum (
  'masse', 'longueur', 'surface', 'volume', 'comptage'
);

create type production.contexte_production as enum (
  'plein_champ', 'serre'
);

create type production.statut_culture as enum (
  'prevue', 'validee', 'semee', 'plantee', 'en_recolte', 'terminee', 'annulee'
);

create type production.origine_donnee as enum (
  'calculee', 'forcee'
);

create type production.type_occupation as enum (
  'culture', 'engrais_vert', 'repos', 'materiel'
);

create type production.mode_emprise as enum (
  'planches', 'metrique'
);

create type production.sens_implantation as enum (
  'croissant', 'decroissant'
);


-- ============================================================================
-- Unités de mesure
-- En table, pas en type énuméré : la liste vit.
-- Exception assumée à la convention uuid : la clé primaire est le code.
-- Ces valeurs sont référencées partout, et « kg » se relit mieux qu'un uuid
-- dans une requête écrite à la main. Dis-le si tu préfères l'homogénéité.
-- ============================================================================

create table production.unite (
  code                text primary key,
  libelle             text not null,
  dimension           production.dimension_unite not null,
  unite_base          text references production.unite (code),
  facteur_conversion  numeric(16,6),
  constraint unite_base_coherente check (
    (unite_base is null and facteur_conversion is null)
    or (unite_base is not null and facteur_conversion is not null
        and facteur_conversion > 0)
  )
);

comment on table production.unite is
  'Unités de mesure. La conversion graines <-> grammes ne figure pas ici : '
  'elle dépend du PMG de chaque variété.';

insert into production.unite (code, libelle, dimension, unite_base, facteur_conversion) values
  ('g',       'gramme',            'masse',    null,  null),
  ('kg',      'kilogramme',        'masse',    'g',   1000),
  ('t',       'tonne',             'masse',    'g',   1000000),
  ('m',       'mètre',             'longueur', null,  null),
  ('cm',      'centimètre',        'longueur', 'm',   0.01),
  ('m2',      'mètre carré',       'surface',  null,  null),
  ('a',       'are',               'surface',  'm2',  100),
  ('ha',      'hectare',           'surface',  'm2',  10000),
  ('L',       'litre',             'volume',   null,  null),
  ('mL',      'millilitre',        'volume',   'L',   0.001),
  ('u',       'unité',             'comptage', null,  null),
  ('graines', 'graines',           'comptage', 'u',   1),
  ('plants',  'plants',            'comptage', 'u',   1),
  ('caisses', 'caisses',           'comptage', null,  null),
  ('mottes',  'mottes',            'comptage', 'u',   1);


-- ============================================================================
-- Entités juridiques
-- Une information portée par l'îlot. Aucune logique ne s'appuie dessus.
-- ============================================================================

create table production.entite_juridique (
  id      uuid primary key default gen_random_uuid(),
  code    text not null unique,
  nom     text not null,
  forme   text,
  siret   text,
  actif   boolean not null default true
);


-- ============================================================================
-- Journal d'audit
-- Alimenté par trigger, jamais à la main. Répond à « qu'est-ce que j'ai
-- modifié en juin ? » sur tous les champs à la fois, et porte l'historique
-- des PMG et des prix sans table dédiée.
-- ============================================================================

create table production.historique (
  id          bigint generated always as identity primary key,
  table_nom   text        not null,
  ligne_id    uuid        not null,
  operation   text        not null check (operation in ('INSERT','UPDATE','DELETE')),
  modifie_le  timestamptz not null default now(),
  auteur_id   uuid,
  avant       jsonb,
  apres       jsonb
);

create index historique_ligne_idx on production.historique (table_nom, ligne_id, modifie_le desc);
create index historique_date_idx  on production.historique (modifie_le desc);

-- L'auteur vient du JWT quand la requête passe par un utilisateur authentifié,
-- et d'une variable de session quand elle passe par une Edge Function en
-- service_role. Celle-ci pose la variable avant d'écrire :
--   select set_config('app.auteur_id', '<uuid>', true);
create or replace function production.auteur_courant()
returns uuid
language plpgsql
stable
as $$
declare
  v text;
begin
  begin
    v := current_setting('request.jwt.claims', true)::jsonb ->> 'sub';
  exception when others then
    v := null;
  end;
  if v is null or v = '' then
    v := nullif(current_setting('app.auteur_id', true), '');
  end if;
  return v::uuid;
exception when others then
  return null;
end;
$$;

create or replace function production.tracer_historique()
returns trigger
language plpgsql
security definer
set search_path = production, pg_catalog
as $$
declare
  v_id uuid;
begin
  v_id := coalesce((to_jsonb(new) ->> 'id')::uuid, (to_jsonb(old) ->> 'id')::uuid);

  if tg_op = 'UPDATE' and to_jsonb(old) = to_jsonb(new) then
    return new;
  end if;

  insert into production.historique (table_nom, ligne_id, operation, auteur_id, avant, apres)
  values (
    tg_table_name,
    v_id,
    tg_op,
    production.auteur_courant(),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );

  return coalesce(new, old);
end;
$$;

comment on function production.tracer_historique is
  'Trigger générique d''audit. À poser sur toute table dont les modifications '
  'doivent être retrouvables : create trigger <table>_audit after insert or '
  'update or delete on production.<table> for each row execute function '
  'production.tracer_historique();';


-- ============================================================================
-- Horodatage automatique
-- Pose une date de mise à jour quand, et seulement quand, la colonne surveillée
-- change. Sert à pmg_mis_a_jour_le, tarif.mis_a_jour_le, etc.
-- Ces dates ne se saisissent jamais.
-- ============================================================================

create or replace function production.horodater_si_change()
returns trigger
language plpgsql
as $$
declare
  col_surveillee text := tg_argv[0];
  col_date       text := tg_argv[1];
  j_old jsonb := to_jsonb(old);
  j_new jsonb := to_jsonb(new);
begin
  if tg_op = 'INSERT' or j_old -> col_surveillee is distinct from j_new -> col_surveillee then
    new := jsonb_populate_record(new, jsonb_build_object(col_date, now()));
  end if;
  return new;
end;
$$;


-- ============================================================================
-- Droits
-- Reprend le motif éprouvé de suivi-temps : anon en lecture seule, toutes les
-- écritures par Edge Function en service_role, qui contourne RLS et revalide
-- les règles côté serveur.
-- ============================================================================

grant usage on schema production to anon, authenticated, service_role;

alter default privileges in schema production
  grant select on tables to anon, authenticated;

grant select on all tables in schema production to anon, authenticated;

alter table production.unite             enable row level security;
alter table production.entite_juridique  enable row level security;
alter table production.historique        enable row level security;

create policy unite_lecture on production.unite
  for select to anon, authenticated using (true);

create policy entite_lecture on production.entite_juridique
  for select to anon, authenticated using (true);

-- Le journal d'audit n'est pas lisible par le client : il contient l'avant/après
-- de toutes les tables. Il se consulte par Edge Function.
