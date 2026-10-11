-- ============================================================================
-- Plan de culture maraîchère — 007 · Affinages de la pré-affectation
-- Unicité des pré-affectations, et repli de la métrique d'îlot sur les
-- planches temporaires.
-- ============================================================================


-- ============================================================================
-- Unicité : une pré-affectation par objet et par cible, dans une campagne
--
-- Quatre contraintes, une par combinaison autorisée par les contraintes
-- preaffectation_objet_unique et preaffectation_cible_unique de 006 :
-- groupe ou culture, îlot ou parcelle.
--
-- Une contrainte UNIQUE ordinaire suffit, sans index partiel : en Postgres les
-- NULL sont DISTINCTS dans un index unique, donc chaque contrainte ne mord que
-- sur les lignes dont les TROIS colonnes sont renseignées — exactement sa
-- combinaison. Une pré-affectation « culture sur parcelle » laisse
-- groupe_assolement_id et ilot_id à NULL : elle n'est jamais vue comme un
-- doublon par les trois autres contraintes.
--
-- Scinder un groupe sur DEUX îlots reste possible — les cibles diffèrent. Ce
-- qui est fermé, c'est le doublon sur une MÊME cible, parce qu'il faussait le
-- « placé » de v_preaffectation_solde : chaque ligne y voit la totalité des
-- affectations de sa cible, pas sa part. Deux lignes de 300 m² sur le même
-- groupe et le même îlot affichaient chacune un reste de -300.
-- ============================================================================

alter table production.preaffectation
  add constraint preaffectation_groupe_ilot_unique
    unique (campagne_id, groupe_assolement_id, ilot_id),
  add constraint preaffectation_groupe_parcelle_unique
    unique (campagne_id, groupe_assolement_id, parcelle_id),
  add constraint preaffectation_culture_ilot_unique
    unique (campagne_id, culture_id, ilot_id),
  add constraint preaffectation_culture_parcelle_unique
    unique (campagne_id, culture_id, parcelle_id);


-- ============================================================================
-- Métrique d'un îlot — repli sur les planches temporaires
--
-- La version de 006 ne retenait que les unités permanentes. Or sous serre les
-- unités sont rattachées à une campagne et refaites chaque année : un îlot de
-- serres n'avait donc aucune métrique, et les colonnes « en planches » de
-- v_preaffectation_solde tombaient à NULL alors que les mètres carrés étaient
-- justes.
--
-- Désormais : les planches permanentes quand il en existe dans l'îlot, ses
-- planches temporaires sinon. Le repli se décide par ÎLOT, pas par parcelle.
--
-- create or replace, et non drop : v_preaffectation_solde dépend de cette vue,
-- un drop cascade la supprimerait. Les colonnes conservent donc exactement
-- leurs noms, leur ordre et leurs types.
-- ============================================================================

create or replace view production.v_ilot_metrique as
with unites as (
  select
    p.ilot_id,
    u.id,
    u.longueur_m,
    u.largeur_m,
    u.surface_occupee_m2,
    u.permanente
  from production.parcelle p
  join production.unite_culture u
    on u.parcelle_id = p.id and u.actif
  where p.actif
),
retenues as (
  select un.*
  from unites un
  where un.permanente
     or not exists (
          select 1
          from unites perm
          where perm.ilot_id = un.ilot_id
            and perm.permanente
        )
)
select
  i.id                                                   as ilot_id,
  i.code,
  i.nom,
  count(r.id)                                            as nb_planches,
  mode() within group (order by r.longueur_m)            as longueur_planche_m,
  mode() within group (order by r.largeur_m)             as largeur_planche_m,
    mode() within group (order by r.longueur_m)
  * mode() within group (order by r.largeur_m)           as surface_planche_m2,
  coalesce(sum(r.longueur_m), 0)                         as longueur_totale_m,
  coalesce(sum(r.surface_occupee_m2), 0)                 as surface_totale_m2
from production.ilot i
left join retenues r on r.ilot_id = i.id
group by i.id, i.code, i.nom;

comment on view production.v_ilot_metrique is
  'Longueur de planche dominante par îlot. C''est elle qui convertit une '
  'surface en nombre de planches : 180 m donne des planches de 306 m², '
  '120 m des planches de 204 m². Repli : un îlot sans aucune planche '
  'permanente active est mesuré sur ses planches temporaires — cas des '
  'serres, dont les unités sont refaites à chaque campagne.';

-- CREATE OR REPLACE VIEW ne garantit pas la conservation des options de la
-- vue : on repose security_invoker explicitement. Les droits, eux, survivent
-- (la vue n'est pas recréée, son OID ne change pas).
alter view production.v_ilot_metrique set (security_invoker = true);
