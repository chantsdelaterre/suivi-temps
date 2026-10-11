-- ============================================================================
-- Plan de culture maraîchère — 006 · Pré-affectation
-- Le placement grossier, qu'on affine ensuite : « le groupe Salade 1 va sur
-- l'îlot 03, on verra les parcelles plus tard ».
--
-- L'unité stockée est la SURFACE, parce que c'est elle qui ne bouge pas.
-- 612 m² font 2 planches sur un îlot à 180 m et 3 planches sur un îlot à
-- 120 m : c'est l'appli qui convertit, selon la longueur des planches de
-- l'îlot visé. Déplacer un groupe d'un îlot à l'autre ne change pas la
-- surface, seulement le nombre de planches.
-- ============================================================================

create table production.preaffectation (
  id                    uuid primary key default gen_random_uuid(),
  campagne_id           uuid not null references production.campagne (id) on delete cascade,

  -- Ce qu'on place : un groupe d'assolement, ou une culture isolée.
  groupe_assolement_id  uuid references production.groupe_assolement (id),
  culture_id            uuid references production.culture (id) on delete cascade,

  -- Où on le place : un îlot, ou directement une parcelle.
  ilot_id               uuid references production.ilot (id),
  parcelle_id           uuid references production.parcelle (id),

  surface_prevue_m2     numeric(12,2) not null check (surface_prevue_m2 > 0),
  origine               production.origine_donnee not null default 'forcee',
  note                  text,

  constraint preaffectation_objet_unique check (
    (groupe_assolement_id is not null)::int + (culture_id is not null)::int = 1
  ),
  constraint preaffectation_cible_unique check (
    (ilot_id is not null)::int + (parcelle_id is not null)::int = 1
  )
);

create index preaffectation_campagne_idx on production.preaffectation (campagne_id);
create index preaffectation_groupe_idx   on production.preaffectation (groupe_assolement_id);
create index preaffectation_culture_idx  on production.preaffectation (culture_id);
create index preaffectation_ilot_idx     on production.preaffectation (ilot_id);
create index preaffectation_parcelle_idx on production.preaffectation (parcelle_id);

comment on table production.preaffectation is
  'L''étape qui manquait entre le besoin et l''implantation. On pose un '
  'groupe d''assolement sur un îlot, puis on descend aux parcelles et aux '
  'planches. Une pré-affectation sans affectation n''est pas une anomalie : '
  'c''est un travail en cours.';

comment on column production.preaffectation.surface_prevue_m2 is
  'La surface, seule grandeur qui survive à un déplacement d''îlot. La '
  'saisie peut se faire en planches : l''interface multiplie par la surface '
  'de planche de l''îlot visé avant d''enregistrer.';


-- ============================================================================
-- Métrique d'un îlot
-- La longueur de planche dominante, d'où se déduit tout le reste.
-- ============================================================================

create view production.v_ilot_metrique as
select
  i.id                                                   as ilot_id,
  i.code,
  i.nom,
  count(u.id)                                            as nb_planches,
  mode() within group (order by u.longueur_m)            as longueur_planche_m,
  mode() within group (order by u.largeur_m)             as largeur_planche_m,
    mode() within group (order by u.longueur_m)
  * mode() within group (order by u.largeur_m)           as surface_planche_m2,
  coalesce(sum(u.longueur_m), 0)                         as longueur_totale_m,
  coalesce(sum(u.surface_occupee_m2), 0)                 as surface_totale_m2
from production.ilot i
left join production.parcelle p
  on p.ilot_id = i.id and p.actif
left join production.unite_culture u
  on u.parcelle_id = p.id and u.permanente and u.actif
group by i.id, i.code, i.nom;

comment on view production.v_ilot_metrique is
  'Longueur de planche dominante par îlot. C''est elle qui convertit une '
  'surface en nombre de planches : 180 m donne des planches de 306 m², '
  '120 m des planches de 204 m².';


-- ============================================================================
-- Le solde : prévu, placé, reste à placer
-- Les deux chiffres qui doivent rester à l'écran pendant qu'on construit
-- le plan.
-- ============================================================================

create view production.v_preaffectation_solde as
select
  pa.id,
  pa.campagne_id,
  pa.groupe_assolement_id,
  pa.culture_id,
  pa.ilot_id,
  pa.parcelle_id,
  pa.surface_prevue_m2,

  im.longueur_planche_m,
  im.surface_planche_m2,

  case when im.surface_planche_m2 > 0
       then round(pa.surface_prevue_m2 / im.surface_planche_m2, 2)
  end                                                    as nb_planches_prevues,

  s.surface_placee_m2,

  case when im.surface_planche_m2 > 0
       then round(s.surface_placee_m2 / im.surface_planche_m2, 2)
  end                                                    as nb_planches_placees,

  pa.surface_prevue_m2 - s.surface_placee_m2             as reste_a_placer_m2,

  case when im.surface_planche_m2 > 0
       then round((pa.surface_prevue_m2 - s.surface_placee_m2)
                  / im.surface_planche_m2, 2)
  end                                                    as reste_a_placer_planches

from production.preaffectation pa

left join production.v_ilot_metrique im
  on im.ilot_id = coalesce(
       pa.ilot_id,
       (select p.ilot_id from production.parcelle p where p.id = pa.parcelle_id)
     )

left join lateral (
  select coalesce(sum(va.surface_occupee_m2), 0) as surface_placee_m2
  from production.v_affectation va
  join production.culture  c on c.id = va.culture_id
  join production.parcelle p on p.id = va.parcelle_id
  where c.campagne_id = pa.campagne_id
    and c.statut <> 'annulee'
    and (
          (pa.culture_id is not null and c.id = pa.culture_id)
       or (pa.groupe_assolement_id is not null
           and c.groupe_assolement_id = pa.groupe_assolement_id)
        )
    and (
          (pa.ilot_id is not null and p.ilot_id = pa.ilot_id)
       or (pa.parcelle_id is not null and p.id = pa.parcelle_id)
        )
) s on true;

comment on view production.v_preaffectation_solde is
  'Prévu, placé, reste à placer — en mètres carrés et en planches de l''îlot '
  'visé. Un reste positif n''est pas une erreur : c''est le travail qui '
  'reste.';


-- ============================================================================
-- Journal d'audit
-- ============================================================================

create trigger preaffectation_audit after insert or update or delete on production.preaffectation
  for each row execute function production.tracer_historique();


-- ============================================================================
-- Droits
-- ============================================================================

alter table production.preaffectation enable row level security;

create policy preaffectation_lecture on production.preaffectation
  for select to anon, authenticated using (true);

grant select on production.preaffectation         to anon, authenticated;
grant select on production.v_ilot_metrique        to anon, authenticated;
grant select on production.v_preaffectation_solde to anon, authenticated;

alter view production.v_ilot_metrique        set (security_invoker = true);
alter view production.v_preaffectation_solde set (security_invoker = true);
