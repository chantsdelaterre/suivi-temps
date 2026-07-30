# BACKLOG — suivi-temps

Points relevés au fil de l'eau, hors chantier courant. Priorité indicative.

## Priorité moyenne

- **Contrôle de statut de période absent des écritures paie** : `ajuster-paie` et
  `valider-recap` ne lisent JAMAIS `periodes` → aucun contrôle de statut, **une
  période clôturée reste modifiable**. Trou préexistant, hors chantier lot 1, à
  refermer.
- **`calculerCountsPaie` — volume** : rapatrie toutes les lignes de `paie_detail`
  de toutes les périodes pour n'en tirer qu'un `count(distinct collab_id)`
  (~20 000 lignes/an). La pagination **repousse le mur, ne le supprime pas**.
  Cible : une **RPC d'agrégation** renvoyant les compteurs par période.
- **Resynchroniser la doc du schéma** : les colonnes `nb_at` / `nb_cs` existent en
  base (integer, default 0, ajoutées par un ALTER non tracé) mais sont **absentes
  du SQL versionné** → resynchroniser `SCHEMA_REEL.md` ET `sql/recap_paie.sql`.
  Profiter de l'occasion pour **documenter `jours` en base** (aucun `CREATE TABLE`
  versionné).

## Priorité basse

- **`chargerRecap` non borné** : lit tout l'historique des `jours` sans borne. Non
  critique — le tri décroissant fait que la troncature garde les lignes **RÉCENTES**,
  et la fonction ne cherche que la dernière saisie. Cas résiduel : un collab sans
  saisie depuis **plus que la fenêtre rapatriée** afficherait « — » à tort.
- **Coût de lecture de l'onglet Paie** : ~1 Mo par ouverture de détail (lecture des
  jours + des couples `paie_detail` à chaque fois, même quand tout est à jour).
  Optimisation possible par **comparaison de deux count**, mais elle suppose que
  **rien ne supprime jamais de lignes dans `jours`** — non vérifié.
- **Code mort à supprimer** : `calculerPaiePeriode`, `rechargerDetailPaie`.
- **Pièges DOM / accessibilité (admin-v2)** : panneau Issues de Chrome = **2
  « Duplicate form field id in the same form »** et **17 « No label associated with
  a form field »**. Aucun impact d'exécution, mais les **id dupliqués sont un piège
  pour `getElementById`** — à regarder **AVANT** de réutiliser l'écran d'ajustement
  depuis un autre onglet.
