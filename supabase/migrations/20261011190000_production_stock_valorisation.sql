-- ============================================================================
-- Plan de culture maraîchère — 011 · Valorisation du stock à la bonne unité
-- valeur_estimee tient compte de tarif.unite_prix.
-- ============================================================================

-- ============================================================================
-- Ce que ce fichier corrige
--
-- 010 a rendu quantite homogène, exprimée dans l'unité de vente. Mais
-- valeur_estimee la multipliait par tarif.prix_achat SANS regarder
-- tarif.unite_prix : un tarif saisi au kilo appliqué à des graines donnait une
-- valorisation absurde. Même nature d'erreur que celle de 010, un cran plus
-- loin dans le calcul.
--
-- Le sens de la conversion est l'INVERSE de celui des quantités : on ramène la
-- quantité vers l'unité du PRIX, puis on multiplie. C'est équivalent à
-- convertir le prix vers l'unité de vente — la conversion étant linéaire — mais
-- cela s'écrit avec convertir_quantite telle qu'elle est, sans l'inverser.
--
-- Deux règles, posées explicitement :
--   - unite_prix NULL signifie « même unité que la vente » : le prix s'applique
--     directement, aucune conversion. La colonne porte une FK vers unite(code),
--     donc NULL est la seule forme de vide possible.
--   - si la conversion échoue, PAS DE VALORISATION — valeur_estimee vaut NULL,
--     jamais un chiffre faux.
--
-- Conséquence assumée, dans le même esprit : une variété SANS tarif n'est plus
-- valorisée à 0 mais à NULL. Un stock de 500 graines à 0 € est un chiffre faux,
-- pas une valeur nulle ; l'interface a de toute façon désormais à traiter le
-- NULL, puisque c'est aussi ce que renvoie une conversion impossible.
--
-- L'agrégation passe en CTE : l'expression de quantite était déjà écrite deux
-- fois dans 010, valeur_estimee en aurait fait une troisième. Elle n'est plus
-- calculée qu'une fois, et les colonnes gardent noms, ordre et types.
-- ============================================================================

create or replace view production.v_stock as
with dernier_inventaire as (
  select distinct on (variete_id)
    variete_id, date, quantite, unite, prix_unitaire
  from production.mouvement_stock
  where type = 'inventaire'
  order by variete_id, date desc, id desc
),
agrege as (
  select
    v.id                                 as variete_id,
    v.code,
    v.nom,
    v.legume_id,
    v.unite_vente,
    v.pmg,
    v.graines_par_gramme,
    di.date                              as date_inventaire,

    coalesce(
      production.convertir_quantite(di.quantite, di.unite, v.unite_vente, v.graines_par_gramme),
      0
    )
    + coalesce(
        sum(
          production.convertir_quantite(m.quantite, m.unite, v.unite_vente, v.graines_par_gramme)
        ) filter (where di.date is null or m.date > di.date),
        0
      )                                  as quantite,

    t.prix_achat,
    t.unite_prix,

    count(*) filter (
      where m.id is not null
        and (di.date is null or m.date > di.date)
        and production.convertir_quantite(m.quantite, m.unite, v.unite_vente, v.graines_par_gramme) is null
    )
    + case
        when di.quantite is not null
         and production.convertir_quantite(di.quantite, di.unite, v.unite_vente, v.graines_par_gramme) is null
        then 1 else 0
      end                                as mouvements_non_convertis

  from production.variete v
  left join dernier_inventaire di on di.variete_id = v.id
  left join production.mouvement_stock m
    on m.variete_id = v.id and m.type <> 'inventaire'
  left join lateral (
    select ta.prix_achat, ta.unite_prix
    from production.tarif ta
    where ta.variete_id = v.id
    order by ta.mis_a_jour_le desc nulls last
    limit 1
  ) t on true
  where v.actif
  group by v.id, v.code, v.nom, v.legume_id, v.unite_vente, v.pmg,
           v.graines_par_gramme, di.date, di.quantite, di.unite,
           t.prix_achat, t.unite_prix
)
select
  a.variete_id,
  a.code,
  a.nom,
  a.legume_id,
  a.unite_vente,
  a.pmg,
  a.graines_par_gramme,
  a.date_inventaire,
  a.quantite,
  a.unite_vente                          as unite,
  a.prix_achat,

  case
    -- Aucun tarif connu : pas de valorisation, et surtout pas zéro.
    when a.prix_achat is null then null
    -- unite_prix vide = même unité que la vente : le prix s'applique tel quel.
    when a.unite_prix is null or a.unite_prix = a.unite_vente
      then a.quantite * a.prix_achat
    -- Sinon on ramène la quantité vers l'unité du prix. Si la conversion
    -- échoue, elle vaut NULL et la valorisation disparaît avec elle.
    else production.convertir_quantite(
           a.quantite, a.unite_vente, a.unite_prix, a.graines_par_gramme
         ) * a.prix_achat
  end                                    as valeur_estimee,

  a.mouvements_non_convertis

from agrege a;

comment on view production.v_stock is
  'Stock courant par variété, reparti du dernier inventaire, exprimé dans '
  'l''unité de vente de la variété — chaque mouvement y est converti avant '
  'd''être additionné. La valeur est estimée au dernier prix d''achat connu, '
  'ramené à l''unité de vente ; le coût réellement engagé, lui, vit dans les '
  'lignes de commande.';

comment on column production.v_stock.quantite is
  'Somme homogène, exprimée dans unite_vente. Les mouvements inconvertibles en '
  'sont écartés : la quantité est donc partielle dès que '
  'mouvements_non_convertis dépasse 0.';

comment on column production.v_stock.unite is
  'L''unité dans laquelle quantite est exprimée, soit l''unité de vente de la '
  'variété. N''est plus celle du dernier inventaire, puisque celui-ci est '
  'désormais converti comme le reste.';

comment on column production.v_stock.valeur_estimee is
  'Quantité ramenée à l''unité du tarif, multipliée par le prix d''achat. '
  'NULL — et non zéro — quand il n''y a pas de tarif, ou quand la conversion '
  'entre l''unité de vente et celle du prix est impossible : pas de '
  'valorisation plutôt qu''un chiffre faux. Un unite_prix vide signifie '
  '« même unité que la vente ».';

comment on column production.v_stock.mouvements_non_convertis is
  'Nombre de quantités écartées de la somme faute de conversion possible, '
  'inventaire de départ compris. Au-delà de 0, quantite et valeur_estimee '
  'sont partielles et l''interface doit le dire. Causes : unité en caisses, '
  'variété sans PMG pour franchir masse <-> comptage, ou sans unité de vente.';

-- Reposé explicitement : un remplacement de vue ne garantit pas la
-- conservation de ses options. Les droits survivent, l'OID ne changeant pas.
alter view production.v_stock set (security_invoker = true);
