-- ============================================================================
-- Plan de culture maraîchère — 008 · Signaler le repli de la métrique d'îlot
-- Une colonne pour que l'interface sache sur quoi elle calcule.
-- ============================================================================

-- ============================================================================
-- v_ilot_metrique : ajout de metrique_de_repli
--
-- 007 a donné une métrique aux îlots de serres, mais sans dire qu'elle venait
-- de planches temporaires — refaites à chaque campagne, donc susceptibles de
-- changer. « Planches de 204 m² » et « planches de 204 m² cette année-là » ne
-- s'affichent pas de la même façon.
--
-- La colonne est ajoutée EN FIN de liste : create or replace view n'autorise
-- que cela, les neuf colonnes existantes gardant leurs noms, leur ordre et
-- leurs types. Si ce n'était pas le cas, la migration échouerait — ce qui fait
-- de son succès la preuve que rien n'a bougé en amont.
--
-- bool_and(not permanente) plutôt qu'un coalesce vers false : par construction
-- de la CTE retenues, les unités d'un îlot sont soit toutes permanentes, soit
-- toutes temporaires, jamais mélangées. La valeur se lit donc sans ambiguïté :
--   false = métrique assise sur des planches permanentes ;
--   true  = repli, aucune planche permanente dans l'îlot ;
--   NULL  = aucune planche du tout, donc aucune métrique — la colonne est nulle
--           exactement quand longueur_planche_m l'est, ce qui évite à
--           l'interface un troisième cas à traiter.
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
  coalesce(sum(r.surface_occupee_m2), 0)                 as surface_totale_m2,
  bool_and(not r.permanente)                             as metrique_de_repli
from production.ilot i
left join retenues r on r.ilot_id = i.id
group by i.id, i.code, i.nom;

comment on view production.v_ilot_metrique is
  'Longueur de planche dominante par îlot. C''est elle qui convertit une '
  'surface en nombre de planches : 180 m donne des planches de 306 m², '
  '120 m des planches de 204 m². Repli : un îlot sans aucune planche '
  'permanente active est mesuré sur ses planches temporaires — cas des '
  'serres, dont les unités sont refaites à chaque campagne.';

comment on column production.v_ilot_metrique.metrique_de_repli is
  'Sur quoi la métrique est assise. false : des planches permanentes. '
  'true : repli sur des planches temporaires, qui changeront à la campagne '
  'suivante — à signaler dans l''interface. NULL : aucune planche, donc '
  'aucune métrique (la colonne est nulle exactement quand '
  'longueur_planche_m l''est).';

-- Reposé explicitement : un remplacement de vue ne garantit pas la
-- conservation de ses options. Les droits survivent, l'OID ne changeant pas.
alter view production.v_ilot_metrique set (security_invoker = true);
