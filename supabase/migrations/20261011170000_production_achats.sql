-- ============================================================================
-- Plan de culture maraîchère — 009 · Stock et achats
-- Dernier fichier de l'étape 1.
-- Le stock comme somme de mouvements, les prix figés à l'achat.
-- ============================================================================

create type production.type_mouvement_stock as enum (
  'achat', 'semis', 'perte', 'inventaire', 'correction'
);

create type production.statut_commande as enum (
  'brouillon', 'envoyee', 'confirmee', 'livree', 'annulee'
);

create type production.type_fourniture as enum (
  'semence', 'plant', 'voile', 'autre'
);


-- ============================================================================
-- Commandes
-- ============================================================================

create table production.commande (
  id                     uuid primary key default gen_random_uuid(),
  reference              text unique,
  fournisseur_id         uuid not null references production.fournisseur (id),
  campagne_id            uuid references production.campagne (id),
  date_commande          date,
  date_livraison_prevue  date,
  date_livraison_reelle  date,
  statut                 production.statut_commande not null default 'brouillon',
  note                   text
);

create index commande_fournisseur_idx on production.commande (fournisseur_id);
create index commande_campagne_idx    on production.commande (campagne_id);


-- ============================================================================
-- Lignes de commande
-- Fige le prix et le conditionnement au moment de l'achat. Annuler une
-- culture en juin ne doit pas réécrire ce qui a été dépensé en février.
-- ============================================================================

create table production.commande_ligne (
  id                      uuid primary key default gen_random_uuid(),
  commande_id             uuid not null references production.commande (id) on delete cascade,
  type_fourniture         production.type_fourniture not null,
  variete_id              uuid references production.variete (id),
  materiel_vegetal_id     uuid references production.materiel_vegetal (id),
  equipement_id           uuid references production.equipement (id),
  culture_id              uuid references production.culture (id) on delete set null,

  designation             text not null,
  reference_fournisseur   text,
  quantite                numeric(12,3) not null check (quantite > 0),
  unite                   text references production.unite (code),
  prix_unitaire_fige      numeric(12,4) check (prix_unitaire_fige >= 0),
  conditionnement_fige    numeric(12,3),
  note                    text,

  montant numeric(16,4)
    generated always as (quantite * prix_unitaire_fige) stored
);

create index commande_ligne_commande_idx on production.commande_ligne (commande_id);
create index commande_ligne_variete_idx  on production.commande_ligne (variete_id);
create index commande_ligne_culture_idx  on production.commande_ligne (culture_id);

comment on column production.commande_ligne.designation is
  'Le libellé envoyé au fournisseur, dans sa langue. Repris de '
  'tarif.designation_fournisseur au moment de la commande, puis figé : une '
  'correction du catalogue ne doit pas réécrire une commande partie.';

comment on column production.commande_ligne.prix_unitaire_fige is
  'Le prix au moment de l''achat. C''est lui qui fait foi pour le coût d''une '
  'campagne, pas le tarif courant.';


-- ============================================================================
-- Mouvements de stock
-- Le stock n'est jamais un champ qu'on écrase : c'est la somme de ce qui est
-- entré et sorti. Le comptage du 31/12 est un mouvement d'inventaire.
-- ============================================================================

create table production.mouvement_stock (
  id                 uuid primary key default gen_random_uuid(),
  variete_id         uuid not null references production.variete (id),
  date               date not null default current_date,
  type               production.type_mouvement_stock not null,
  quantite           numeric(12,3) not null,
  unite              text not null references production.unite (code),
  prix_unitaire      numeric(12,4) check (prix_unitaire >= 0),
  commande_ligne_id  uuid references production.commande_ligne (id) on delete set null,
  culture_id         uuid references production.culture (id) on delete set null,
  note               text
);

create index mouvement_variete_idx on production.mouvement_stock (variete_id, date);
create index mouvement_date_idx    on production.mouvement_stock (date);

comment on column production.mouvement_stock.quantite is
  'Positive pour une entrée, négative pour une sortie. Un inventaire porte '
  'la quantité comptée, pas l''écart : c''est la vue qui fait la différence.';

comment on column production.mouvement_stock.prix_unitaire is
  'Coût réel de cette entrée, hérité de la ligne de commande. Permet de '
  'valoriser le stock sans rien réécrire rétroactivement.';


-- ============================================================================
-- État du stock
-- Depuis le dernier inventaire s'il y en a un, depuis l'origine sinon.
-- La conversion graines <-> grammes passe par le PMG de la variété.
-- ============================================================================

create view production.v_stock as
with dernier_inventaire as (
  select distinct on (variete_id)
    variete_id, date, quantite, unite, prix_unitaire
  from production.mouvement_stock
  where type = 'inventaire'
  order by variete_id, date desc, id desc
)
select
  v.id                                   as variete_id,
  v.code,
  v.nom,
  v.legume_id,
  v.unite_vente,
  v.pmg,
  v.graines_par_gramme,
  di.date                                as date_inventaire,
  coalesce(di.quantite, 0)
    + coalesce(sum(m.quantite) filter (
        where di.date is null or m.date > di.date
      ), 0)                              as quantite,
  coalesce(di.unite, v.unite_vente)      as unite,
  t.prix_achat,
  (coalesce(di.quantite, 0)
    + coalesce(sum(m.quantite) filter (
        where di.date is null or m.date > di.date
      ), 0))
    * coalesce(t.prix_achat, 0)          as valeur_estimee
from production.variete v
left join dernier_inventaire di on di.variete_id = v.id
left join production.mouvement_stock m
  on m.variete_id = v.id and m.type <> 'inventaire'
left join lateral (
  select ta.prix_achat
  from production.tarif ta
  where ta.variete_id = v.id
  order by ta.mis_a_jour_le desc nulls last
  limit 1
) t on true
where v.actif
group by v.id, v.code, v.nom, v.legume_id, v.unite_vente, v.pmg,
         v.graines_par_gramme, di.date, di.quantite, di.unite, t.prix_achat;

comment on view production.v_stock is
  'Stock courant par variété, reparti du dernier inventaire. La valeur est '
  'estimée au dernier prix d''achat connu ; le coût réellement engagé, lui, '
  'vit dans les lignes de commande.';


-- ============================================================================
-- Besoins en semences et plants
-- L'état que produisait FileMaker, plus le stock et le regroupement par
-- fournisseur.
-- ============================================================================

create view production.v_besoin_plants as
select
  c.campagne_id,
  c.contexte,
  c.legume_id,
  va.variete_id,
  v.code                      as variete_code,
  v.nom                       as variete_nom,
  f.id                        as fournisseur_id,
  f.nom                       as fournisseur_nom,
  i.materiel_vegetal_id,
  sum(va.nb_plants)           as nb_plants,
  sum(va.nb_caisses_retenu)   as nb_caisses,
  sum(va.surface_occupee_m2)  as surface_occupee_m2,
  min(c.date_plantation_prevue) as premiere_plantation
from production.v_affectation va
join production.culture c     on c.id = va.culture_id
left join production.variete v on v.id = va.variete_id
left join production.itineraire i on i.id = va.itineraire_id
left join production.fournisseur f on f.id = c.fournisseur_plants_id
where c.statut <> 'annulee'
group by c.campagne_id, c.contexte, c.legume_id, va.variete_id,
         v.code, v.nom, f.id, f.nom, i.materiel_vegetal_id;

comment on view production.v_besoin_plants is
  'Le besoin par variété, ventilé par contexte — plein champ et serres '
  'distingués, et regroupables pour obtenir le total. Les radis Diablus des '
  'deux mondes s''additionnent sans effort parce qu''ils partagent les mêmes '
  'tables.';


-- ============================================================================
-- Journal d'audit
-- ============================================================================

create trigger commande_audit after insert or update or delete on production.commande
  for each row execute function production.tracer_historique();
create trigger commande_ligne_audit after insert or update or delete on production.commande_ligne
  for each row execute function production.tracer_historique();
create trigger mouvement_stock_audit after insert or update or delete on production.mouvement_stock
  for each row execute function production.tracer_historique();


-- ============================================================================
-- Droits
-- Les prix d'achat et les coûts ne sont pas publics : lecture réservée aux
-- comptes authentifiés, comme les tarifs.
-- ============================================================================

alter table production.commande        enable row level security;
alter table production.commande_ligne  enable row level security;
alter table production.mouvement_stock enable row level security;

create policy commande_lecture on production.commande
  for select to authenticated using (true);
create policy commande_ligne_lecture on production.commande_ligne
  for select to authenticated using (true);
create policy mouvement_stock_lecture on production.mouvement_stock
  for select to authenticated using (true);

grant select on production.commande        to authenticated;
grant select on production.commande_ligne  to authenticated;
grant select on production.mouvement_stock to authenticated;
grant select on production.v_stock         to authenticated;
grant select on production.v_besoin_plants to anon, authenticated;

alter view production.v_stock         set (security_invoker = true);
alter view production.v_besoin_plants set (security_invoker = true);
