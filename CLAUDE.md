# CLAUDE.md

Règles de travail pour ce projet.

## Git & branches
- **Ne JAMAIS pousser (push) sur la branche `main`.** Travailler uniquement sur la branche `supabase`.
- Toujours tester en local avant de proposer un push.

## Stockage des données (Supabase)
- Les heures sont **toujours stockées en texte `HH:mm`** dans Supabase, **jamais** comme objet `Date`.
- `typeJour` : valeurs autorisées `'travaillée'`, `'CP'`, `'AT'` (attention aux accents — `travaillée` avec deux accents).

## Règles métier
- Limite de **3 modifications par jour par collaborateur**, appliquée côté serveur **ET** frontend.

## Modèle des périodes de paie (cadré le 03/06/2026)

- **4 états d'une période** : `planifiee` → `ouverte` → `gelee` → `cloturee`.
  - **`ouverte`** : saisie collaborateur possible. Entrée dans cet état = `date_debut` atteinte (transition **automatique**).
  - **`gelee`** : saisie bloquée. Entrée dans cet état = **lendemain de `date_fin`** (transition **automatique**).
  - **`cloturee`** : paie validée par l'admin. Transition **humaine** (pas automatique).
- **`date_cloture` est ABANDONNÉE** : toute la logique d'ouverture/gel se base désormais sur **`date_debut`** et **`date_fin`** uniquement.

### Verrou de saisie — condition d'AUTORISATION

La saisie d'un jour par un collaborateur est possible **si et seulement si les 4 conditions sont réunies** :

1. **le jour existe en base** (créé par la génération quotidienne) ;
2. **le jour compte moins de 3 enregistrements** — soit **3 enregistrements maximum par jour** : la saisie initiale compte pour 1, puis 2 modifications possibles ; **bloqué dès que `nb_modifications` atteint 3** ;
3. **le jour date de 5 jours ou moins** (J-5 maximum, fenêtre glissante) ;
4. **la période est au statut `ouverte`** — seul ce statut autorise la saisie ; `planifiee`, `gelee` et `cloturee` la **bloquent** toutes.

### État actuel du front (chantier à venir)

`index.html` ne vérifie aujourd'hui que les **3 premières conditions** (existence du jour, max 3 enregistrements, fenêtre 5 jours). Il **ne vérifie PAS encore le statut de la période** (condition 4) : prendre en compte `ouverte` / `gelee` / `cloturee` pour autoriser/bloquer la saisie est un **chantier à venir**.

### Règle de génération des périodes (cadré le 03/06/2026)

- **CIVILES** : un **mois calendaire**. `date_debut` = 1er du mois, `date_fin` = dernier jour du mois. **Pas de calage hebdo.**
- **DÉCALÉES** (**calage lundi→dimanche, automatique**) :
  - `date_fin` = le **premier dimanche ≥ 15** du mois (le 1er dimanche au-delà du 15, ou le 15 lui-même s'il tombe un dimanche).
  - `date_debut` = le **lundi suivant la `date_fin` de la période précédente** (= `date_fin` précédente + 1 jour). **Périodes jointives** par construction.
  - La **durée (4 ou 5 semaines) découle automatiquement** du calendrier — plus aucune décision manuelle.
  - **Vérifié sur 2026** : fins les **19/07, 16/08, 20/09, 18/10**.
- **Génération** : maintenir **2 périodes `planifiee` d'avance par type** (méthode A). La **génération annuelle du 15/11 est reportée** (pas pour l'instant).

## Méthode de travail
- **Éditions chirurgicales uniquement** : ne jamais réécrire un fichier entier.
- **Une seule modification à la fois** : on discute, on valide, ensuite on code.

## Architecture de la paie (cadré le 06/06/2026)

Modèle à **3 niveaux de tables** + un **historique des contrats**. Principe
directeur : *une donnée vit là où est sa logique de changement* — ne pas
mélanger deux temporalités dans une même table. C'est pourquoi le contexte
contractuel n'est **PAS** stocké dans `jours`.

1. **`jours` — saisie collaborateur brute.** Donnée **vivante**, inchangée par
   la paie. C'est la source de saisie quotidienne.

2. **Table « paie » (détail) — à créer.** À la **clôture**, photo **FIGÉE jour
   par jour** des jours validés par l'admin : horaires, `type_jour`, total du
   jour, et un **marqueur des ajustements admin**. Support du **relevé détaillé
   signé**.

3. **Table « récap / synthèse » (= `recap_paie` existante, à ajuster).** **Une
   ligne par collaborateur / période** : totaux **FIGÉS** + contexte
   contractuel **FIGÉ** + workflow (validation, signature, note admin). Les
   totaux sont **calculés depuis le détail puis figés** à la clôture. Support
   **Silae**, **annualisation**, **historique**.

4. **Table « historique des contrats » — à créer.** Colonnes : `collab_id`,
   `date_debut`, `date_fin` (**nulle = contrat en cours**), `structure`,
   `type_contrat`, `heures_hebdo` (+ à compléter). **Une ligne PAR CHANGEMENT**
   (événement rare). Au calcul de paie, on **applique à chaque jour le contrat
   en vigueur à sa date**. Bonus : support de l'**annualisation**.

### Types de jour — deux catégories

Les types de jour se répartissent en **deux catégories distinctes** :

- **Types de SAISIE COLLAB** (table `jours`, posés par le collaborateur) :
  `'travaillée'`, `'CP'`, `'AT'`.
- **Type d'AJUSTEMENT ADMIN** (ajouté en paie, **JAMAIS** posé par le collab) :
  `'CS'` (**Congé Spécial**). Il **illustre le principe directeur** : le `CS`
  naît d'une **décision admin**, il **vit donc au niveau de la table
  paie / ajustements**, pas dans la saisie collab.

### Règles de calcul de la paie (cadré le 06/06/2026)

**Calcul par collaborateur et par période — totaux SÉPARÉS** (pas
d'addition entre eux) :

- **Heures travaillées** = somme des `total_heures` des jours de type
  `'travaillée'` (**en heures**).
- **Heures AT** = somme des jours `'AT'` (**7 h par défaut, MODIFIABLE par
  l'admin**) — **en heures**.
- **Heures CS** = somme des jours `'CS'` (**7 h par défaut, MODIFIABLE par
  l'admin**) — **en heures**.
- **CP** = **nombre de jours** `'CP'` (comptés **en JOURS**, valent **0 h** ; le
  **détail des dates est conservé jour par jour**).

`AT` et `CS` partagent la **même mécanique** : 7 h par défaut, ajustable par
l'admin. Les **valeurs ajustées vivent au niveau de la table paie-détail**.

**Simplification assumée** : le « 7 h par défaut » ne gère **pas
automatiquement** les temps partiels / jours variables (collabs à 4 jours,
2 jours…). **L'admin ajuste manuellement.** Choix **volontaire** pour éviter
une usine à gaz (**pas de table de répartition hebdomadaire**).

**Pour Silae (plus tard)** : les `CP` doivent ressortir en **PLAGES de dates**
(« CP du … au … »), **reconstituées depuis le détail jour par jour**. Cela
**confirme l'intérêt de stocker le détail**.

### Questions encore ouvertes

- **Infos contractuelles exactes** à figer.
- **Ajustements de `recap_paie`** (structure à faire évoluer).

## Plan de bataille — bascule paie sur Supabase (échéance clôture 15/06/2026)

### Avant le 15/06

1. ✅ Sauvegarder l'architecture paie dans `CLAUDE.md` (fait).
2. **Définir les règles de calcul de la paie** — cœur métier sensible, à tête
   reposée.
3. **Créer les tables** : paie-détail, ajuster `recap_paie`, créer
   historique-contrats.
4. **Écrire et tester (à blanc) le script d'import Sheets → Supabase** :
   conversion des dates `jj/mm/aaaa` → ISO, virgules décimales → points.

### Le 15/06 au soir (bascule)

5. **Export Sheets + import réel** dans Supabase : période **`DEC_2026_06`**
   complète (~**300 jours**, **15 collabs**).
6. **Brancher la saisie collab (`index.html`) sur Supabase** pour la période
   suivante (vérifier l'état de cette migration).

### Après le 15 (marge de quelques jours pour traiter la paie)

7. **Outil admin (`admin.html`)** : porter + adapter vers Supabase + ajouter
   récap (totaux calculés), ajustements admin (`AT` / `CS`), validation
   (gel → clôture).
8. **Édition PDF** des relevés détaillés.
9. **Plus tard** : export **Silae**, **annualisation**, **signature**, **front
   manager (`manager.html`)** — souhaité avant le 15 si possible, sinon après.
   - **Suivi annuel des CP** (règle métier à ne pas perdre) : dotation de
     **5 semaines = 5 de CHAQUE jour de semaine** (5 lundis, 5 mardis… 5
     vendredis). Empêche qu'un collab pose **tous** ses CP sur son jour le plus
     lourd. **Contrôle ANNUEL** (lié à l'annualisation), à **plafonner par jour
     de semaine**. Cas **temps partiel à préciser** (dotation =
     5 × nombre de jours travaillés ?). **PAS sur le chemin du 15/06.**

### Filet de sécurité

Si Supabase n'est **pas prêt à temps**, la paie de juin se fait sur
**Sheets / GAS** (porte de sortie, sans stress).

### Contexte front (rappel)

`index.html` gère **désormais** le verrou de période (branché dans
`loadJourDuJour` **et** `ouvrirJourPasse`), avec **messages précis**, **P3**
(sauvegarde pessimiste) et **P4** (`nbModifications` du jour courant). Reste
**non géré** : la consultation de **toute** la période ; le chantier
« **espace collab transparent** » est **reporté après la paie**.

## Bascule collab du 15/06 — reste à faire

**OBJECTIF** : le **15/06**, les saisies collaborateur se font sur **Supabase**
(`index.html`).

### FAIT

- Saisie collab déjà sur Supabase.
- Verrou de période (condition #4) dans `loadJourDuJour` **et** `ouvrirJourPasse`.
- Messages de verrouillage précis (3 modifs / gelée-clôturée / délai 5 j / neutre).
- **P4** : `nbModifications` chargé pour le jour courant (`loadJourDuJour`).
- **P3** : sauvegarde **pessimiste** (« Enregistré » seulement après UPDATE confirmé).
- Script d'import Sheets → Supabase **testé à blanc**.

### RESTE AVANT LE 15

- **#3 (IMPORTANT)** : `fetchMesJoursSupabase` fait `.single()` sur la période
  `ouverte` (~l.1171) → **casse s'il y a 0 ou >1 période ouverte**. Or il y a
  **2 périodes ouvertes en parallèle** (civile + décalée). À corriger
  (`.maybeSingle()` ou filtrage par type/collab) et **tester avec un collègue
  civil ET un décalé**.
- **#4** : le calcul hebdo dans `sauvegarder` (~l.1095-1099) n'a **pas de borne
  de fin de semaine** → il agrège des jours **futurs**. À **borner**.
- **#1 (cosmétique, pas urgent)** : ménage du **code mort GAS** (`API_URL`,
  `jsonpFetch`, `action:'saveHoraires'`).

### CALENDRIER DE BASCULE (dim 14 → lun 15)

- **Dimanche 14 au soir** : import réel **DEC_2026_06** (période **encore
  ouverte**) — ré-export CSV → script → **test rollback** → commit.
- **Nuit du 14 au 15** : le cron **gèle `DEC_2026_06` automatiquement**
  (`date_fin` au 14 désormais passée → `ouverte` → `gelee`).
- **Lundi 15** : bascule équipe — **tout le monde saisit sur Supabase**.
- ⚠️ **Vigilance** : exporter le CSV **APRÈS la dernière saisie du 14**.
  Sinon une saisie tardive serait **écrasée** par le `delete + insert` du script
  d'import.

## Architecture de déploiement & bascule du 15

### PROD ACTUELLE (vérifié dans Settings → Pages)

GitHub Pages sert la branche **`main`** — mode **« Deploy from a branch »**,
dossier **`/ (root)`**. Donc **`main` = 100 % GAS/Sheets** : c'est ce que les
collègues utilisent en ce moment.
Site live : **https://chantsdelaterre.github.io/suivi-temps/**

### BRANCHE `supabase`

Préparation de la bascule : **saisie sur Supabase** + tables/cron/import +
correctifs (verrous, #3, #4). **~35 commits d'avance sur `main`**, **non
déployée** (rien de Supabase n'est servi en prod tant que Pages pointe sur
`main`).

### BASCULE DU 15 — geste recommandé

Dans **Settings → Pages → Build and deployment**, changer la **branche servie**
de `main` à **`supabase`**, puis **Save**.
- **Avantage : `main` reste intacte = ROLLBACK IMMÉDIAT.** En cas de problème,
  il suffit de **remettre `main`** dans le menu pour revenir à la prod GAS/Sheets.
- **Alternative** : merger `supabase` → `main` — mais ça **touche `main`** et
  c'est **moins facile à annuler**. Non retenu par défaut.

### À VÉRIFIER LE 14

Que **`supabase` est bien à jour** (tout poussé sur `origin/supabase`) **avant**
de pointer Pages dessus.

### Hors périmètre de la bascule collab du 15

`admin.html` et `manager.html` sont **encore sur GAS** — **non concernés** par
cette bascule (qui ne porte que sur la saisie collaborateur `index.html`).

### RÈGLE

**Pas de commit/push sur `main`.** La bascule (changement de la branche servie
par Pages) **revient à Guillaume**.
