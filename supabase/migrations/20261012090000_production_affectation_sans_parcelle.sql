-- ============================================================================
-- Plan de culture maraîchère — 014 · Affectation sans parcelle
--
-- FileMaker avait un îlot « indéfini » qui servait à calculer et à commander
-- avant d'avoir choisi les parcelles. Ce n'était pas un défaut : c'est un
-- degré de précision légitime, et le modèle doit le porter.
--
-- Trois degrés, désormais tous exprimables :
--   1. une quantité sans lieu            -> affectation sans parcelle
--   2. une quantité posée sur un îlot    -> preaffectation
--   3. des mètres sur des planches       -> affectation avec parcelle
-- ============================================================================

alter table production.affectation
  alter column parcelle_id drop not null;

comment on column production.affectation.parcelle_id is
  'Facultatif. Vide, l''affectation porte une quantité sans lieu : de quoi '
  'commander les plants avant d''avoir choisi où les mettre. La culture '
  'remonte alors dans le reste à placer, et rien n''apparaît sur le plan.';


-- ============================================================================
-- v_affectation : tolère l'absence de parcelle
-- Largeur de planche standard de 1,70 m quand aucune parcelle n'est choisie —
-- la seule convention nécessaire pour que les surfaces restent calculables.
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

  a.longueur_m * coalesce(p.largeur_planche_m, 1.700)      as surface_occupee_m2,
  a.longueur_m * coalesce(p.largeur_utile_m, 1.400)        as surface_cultivee_m2,
  a.longueur_m * coalesce(p.largeur_planche_m, 1.700) / 204 as equivalent_120,

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

  case when i.espacement_sur_rang_cm > 0
       then floor(a.longueur_m / (i.espacement_sur_rang_cm / 100))
            * cr.nb_rangs * i.graines_par_motte
  end                                                      as nb_graines,

  -- Ajout : distingue une quantité encore sans lieu d'une implantation réelle.
  (a.parcelle_id is null)                                  as sans_parcelle

from production.affectation a
join production.culture  c on c.id = a.culture_id
left join production.parcelle p on p.id = a.parcelle_id
left join production.itineraire i on i.id = c.itineraire_id
left join production.configuration_rangs cr on cr.id = i.configuration_rangs_id;

alter view production.v_affectation set (security_invoker = true);

comment on view production.v_affectation is
  'Les figures de l''affectation : surfaces, plants, caisses, graines. '
  'Une affectation sans parcelle garde des surfaces calculables, sur une '
  'largeur de planche standard de 1,70 m.';


-- ============================================================================
-- Reste à placer d'une campagne
-- Ce qui est commandé mais pas encore implanté. L'écran qui remplace l'îlot
-- « indéfini » de FileMaker.
-- ============================================================================

create view production.v_reste_a_placer as
select
  c.campagne_id,
  c.id                              as culture_id,
  c.code                            as culture_code,
  c.contexte,
  c.legume_id,
  va.variete_id,
  sum(va.longueur_m)                as longueur_m,
  sum(va.surface_occupee_m2)        as surface_occupee_m2,
  sum(va.equivalent_120)            as equivalent_120,
  sum(va.nb_plants)                 as nb_plants,
  sum(va.nb_caisses_retenu)         as nb_caisses
from production.v_affectation va
join production.culture c on c.id = va.culture_id
where va.parcelle_id is null
  and c.statut <> 'annulee'
group by c.campagne_id, c.id, c.code, c.contexte, c.legume_id, va.variete_id;

comment on view production.v_reste_a_placer is
  'Les quantités commandées sans lieu encore choisi. Un reste n''est pas une '
  'anomalie : c''est du travail en cours.';

grant select on production.v_reste_a_placer to anon, authenticated;
alter view production.v_reste_a_placer set (security_invoker = true);
