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
- **Documenter `jours` en base** : aucun `CREATE TABLE` versionné pour cette
  table. `SCHEMA_REEL.md` la liste en section B (colonnes déduites des inserts,
  types non garantis). ✅ Resynchro `SCHEMA_REEL.md` + `sql/recap_paie.sql`
  faite le 09/08/2026 (`nb_at`, `nb_cs`, `date_fin_validation`) — reste `jours`.
- **`garantirEntreeRecapCloture` compare sur `_paieCurrentCollab` brut** alors
  qu'`upsertRecapPaieCourant` **décode d'abord** (`decodeURIComponent`). Sans
  conséquence aujourd'hui (les identifiants viennent de la RPC en clair), mais un
  identifiant contenant un **caractère encodé** casserait le lien.
- **Deux ids dupliqués dans `admin-v2.html`** (panneau Issues de Chrome).
  `modal-note-admin` **ne mord pas aujourd'hui** — l'ordre du HTML fait que
  `getElementById` attrape le bon — mais **ça ne tient qu'à cet ordre**.
- **Lecture de `historique_contrats` dans `calculerPaieDepuisPaieDetail`** : toutes
  les lignes de tous les collabs, **NON paginée**.
- **Message « Aucune période clôturée. »** s'affiche désormais quand il n'y a **ni
  période clôturée ni relevé borné**. « **Aucun relevé clôturé.** » serait plus juste.

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
- **Vestige GAS** : le mapping de libellés de `renderSaisiesPaie` contient
  `ferie:'Férié'` (et `conge`/`absence`) pour des types **qui n'existent pas en
  base**. Piège pour le futur chantier **jours fériés**.
- **Emoji ⏹️** du bloc « Clôtures anticipées » **ne se rend pas** sur macOS Chrome
  (carré vide).
- **Titre « Paie — périodes clôturées » devenu inexact** : la liste peut contenir une
  **période ouverte** portant un relevé borné.
- **`ouvrirDetailArchive` sur une période ouverte** exécute brièvement `renderPaie`
  sur **toute la période** avant de la masquer — **travail inutile, invisible**.
- **`ajuster-paie` n'est pas transactionnelle** : la boucle applique un UPDATE par
  ligne ; un échec en cours laisse les lignes déjà traitées modifiées, avec
  `ajuste_admin` et `date_ajuste_admin` posés sur **une partie seulement** du lot.
  Aucun rollback. Sans conséquence connue (le front n'envoie que les lignes
  réellement modifiées, et l'appel est rejoué à l'identique en cas d'échec), mais à
  savoir.
- **`toggleHeuresEdit` contient un contournement devenu inutile** : il réactive le
  bouton de validation « si badge Validé ». Depuis le 09/08/2026 le bouton n'est
  plus jamais grisé à l'ouverture — la rustine est **redondante, inoffensive**, à
  nettoyer un jour.
