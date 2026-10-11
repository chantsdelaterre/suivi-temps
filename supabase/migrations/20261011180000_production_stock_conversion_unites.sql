-- ============================================================================
-- Plan de culture maraîchère — 010 · Conversion des unités dans v_stock
-- Chaque mouvement est ramené à l'unité de vente de la variété avant d'être
-- additionné.
-- ============================================================================

-- ============================================================================
-- La dette que ce fichier solde
--
-- v_stock (009) faisait sum(m.quantite) sans regarder m.unite, pourtant NOT NULL
-- sur mouvement_stock. Un achat de 500 g et un semis de -2 000 graines donnaient
-- -1500, un nombre qui ne veut rien dire. Juste tant qu'une variété gardait une
-- seule unité, silencieusement faux dès qu'elles se mélangeaient.
--
-- Corrigé pendant que les tables sont vides : aucune donnée à reprendre.
-- ============================================================================


-- ============================================================================
-- Conversion d'une quantité vers une unité cible
--
-- Deux mécaniques, et une seule a besoin du PMG :
--
--   1. DANS une dimension, la table unite suffit. Chaque unité porte son
--      unite_base et son facteur_conversion : kg -> g vaut 1000, graines -> u
--      vaut 1. On ramène à la base commune, puis on divise par le facteur de
--      la cible. Aucune connaissance de la variété nécessaire.
--
--   2. ENTRE masse et comptage, c'est le PMG qui fait le pont, et lui seul :
--      graines_par_gramme = 1000 / pmg, donc grammes * graines_par_gramme donne
--      des graines, et l'inverse en divisant. Propre à chaque variété.
--
-- Renvoie NULL quand la conversion n'a pas de sens, et c'est volontaire :
--   - caisses est une base À PART de la dimension comptage (ni unite_base ni
--     facteur), donc graines -> caisses est indéterminé — il faudrait le
--     conditionnement, qui vit sur la ligne de commande, pas ici ;
--   - L -> g demanderait une densité, que le modèle ne porte pas ;
--   - une variété sans PMG ne peut pas franchir les dimensions ;
--   - une unité inconnue, ou nulle, ne donne aucune ligne à joindre.
--
-- stable et non immutable : la fonction LIT production.unite, dont le contenu
-- peut changer. Pas de security definer — unite est lisible par anon comme par
-- authenticated, donc la fonction fonctionne sous le security_invoker de la vue.
-- ============================================================================

create or replace function production.convertir_quantite(
  p_quantite            numeric,
  p_unite_source        text,
  p_unite_cible         text,
  p_graines_par_gramme  numeric
) returns numeric
language sql
stable
as $$
  with s as (
    select dimension,
           coalesce(facteur_conversion, 1) as facteur,
           coalesce(unite_base, code)      as base
    from production.unite where code = p_unite_source
  ),
  c as (
    select dimension,
           coalesce(facteur_conversion, 1) as facteur,
           coalesce(unite_base, code)      as base
    from production.unite where code = p_unite_cible
  )
  select case
    -- Même dimension et même base : les facteurs suffisent.
    when s.dimension = c.dimension and s.base = c.base
      then p_quantite * s.facteur / c.facteur

    -- Masse -> comptage : grammes * graines par gramme.
    when s.dimension = 'masse'    and s.base = 'g'
     and c.dimension = 'comptage' and c.base = 'u'
     and p_graines_par_gramme > 0
      then p_quantite * s.facteur * p_graines_par_gramme / c.facteur

    -- Comptage -> masse : graines / graines par gramme.
    when s.dimension = 'comptage' and s.base = 'u'
     and c.dimension = 'masse'    and c.base = 'g'
     and p_graines_par_gramme > 0
      then p_quantite * s.facteur / p_graines_par_gramme / c.facteur
  end
  from s, c;
$$;

comment on function production.convertir_quantite is
  'Ramène une quantité d''une unité à une autre. Les facteurs de la table '
  'unite pour les conversions internes à une dimension, le PMG de la variété '
  'pour franchir masse <-> comptage. NULL si la conversion n''a pas de sens '
  '(caisses, volume vers masse, variété sans PMG, unité inconnue).';

grant execute on function production.convertir_quantite(numeric, text, text, numeric)
  to anon, authenticated;


-- ============================================================================
-- v_stock : tout est exprimé dans l'unité de vente de la variété
--
-- La conversion s'applique AUSSI à l'inventaire de départ, pas seulement aux
-- mouvements qui le suivent — un comptage du 31/12 saisi en grammes doit être
-- ramené comme les autres. C'est la raison d'être de la fonction : le même
-- calcul en deux endroits.
--
-- Deux colonnes changent de sens, à noms et types constants :
--   - quantite est désormais une somme homogène ;
--   - unite devient l'unité de vente, et non plus celle du dernier inventaire :
--     c'est maintenant l'unité dans laquelle quantite est exprimée.
--
-- Et une colonne est ajoutée en fin de liste, mouvements_non_convertis. Les
-- quantités inconvertibles sont ÉCARTÉES de la somme plutôt que de la rendre
-- nulle : un seul mouvement douteux ne doit pas masquer tout le stock. Mais une
-- somme amputée en silence serait pire, d'où le compteur — dès qu'il dépasse 0,
-- quantite est partielle et ne doit pas être affichée comme un fait. Même
-- esprit que l'index GiST de 005 : on alerte, on n'interdit pas.
--
-- Une variété sans unite_vente n'a aucune cible : sa quantite vaut 0 et son
-- compteur porte tous ses mouvements.
-- ============================================================================

create or replace view production.v_stock as
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

  coalesce(
    production.convertir_quantite(di.quantite, di.unite, v.unite_vente, v.graines_par_gramme),
    0
  )
  + coalesce(
      sum(
        production.convertir_quantite(m.quantite, m.unite, v.unite_vente, v.graines_par_gramme)
      ) filter (where di.date is null or m.date > di.date),
      0
    )                                    as quantite,

  v.unite_vente                          as unite,
  t.prix_achat,

  (
    coalesce(
      production.convertir_quantite(di.quantite, di.unite, v.unite_vente, v.graines_par_gramme),
      0
    )
    + coalesce(
        sum(
          production.convertir_quantite(m.quantite, m.unite, v.unite_vente, v.graines_par_gramme)
        ) filter (where di.date is null or m.date > di.date),
        0
      )
  ) * coalesce(t.prix_achat, 0)          as valeur_estimee,

  count(*) filter (
    where m.id is not null
      and (di.date is null or m.date > di.date)
      and production.convertir_quantite(m.quantite, m.unite, v.unite_vente, v.graines_par_gramme) is null
  )
  + case
      when di.quantite is not null
       and production.convertir_quantite(di.quantite, di.unite, v.unite_vente, v.graines_par_gramme) is null
      then 1 else 0
    end                                  as mouvements_non_convertis

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
  'Stock courant par variété, reparti du dernier inventaire, exprimé dans '
  'l''unité de vente de la variété — chaque mouvement y est converti avant '
  'd''être additionné. La valeur est estimée au dernier prix d''achat connu ; '
  'le coût réellement engagé, lui, vit dans les lignes de commande.';

comment on column production.v_stock.quantite is
  'Somme homogène, exprimée dans unite_vente. Les mouvements inconvertibles en '
  'sont écartés : la quantité est donc partielle dès que '
  'mouvements_non_convertis dépasse 0.';

comment on column production.v_stock.unite is
  'L''unité dans laquelle quantite est exprimée, soit l''unité de vente de la '
  'variété. N''est plus celle du dernier inventaire, puisque celui-ci est '
  'désormais converti comme le reste.';

comment on column production.v_stock.mouvements_non_convertis is
  'Nombre de quantités écartées de la somme faute de conversion possible, '
  'inventaire de départ compris. Au-delà de 0, quantite et valeur_estimee '
  'sont partielles et l''interface doit le dire. Causes : unité en caisses, '
  'variété sans PMG pour franchir masse <-> comptage, ou sans unité de vente.';

-- Reposé explicitement : un remplacement de vue ne garantit pas la
-- conservation de ses options. Les droits survivent, l'OID ne changeant pas.
alter view production.v_stock set (security_invoker = true);
