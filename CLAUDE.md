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

## Architecture des écritures — Edge Functions (migré le 16/07/2026)

**Principe :** toutes les écritures front passent par des Edge Functions Supabase authentifiées. Le rôle `anon` (clé publishable, publique) est en LECTURE SEULE. Les fonctions écrivent en `service_role`.

**9 Edge Functions** (`supabase/functions/`) :
- `sauver-remarque` — remarque manager (auth `manager_token` + appartenance équipe)
- `sauver-saisie` — saisie collab (auth token collab + appartenance ; recalcul serveur des totaux + règles 3 modifs/jour, J-5, période ouverte)
- `modifier-collab` — édition collab (auth admin, whitelist colonnes)
- `creer-collab` — création collab (auth admin ; génère collab_id + token serveur, appelle la RPC, pose le téléphone)
- `cloturer-periode` — clôture (auth admin + invariant gelee→cloturee)
- `cloturer-contrat` — fin de contrat (auth admin, wrappe la RPC cloturer_contrat)
- `importer-paie` — import bulk paie_detail (auth admin, idempotent)
- `ajuster-paie` — ajustements couche 2 paie_detail (auth admin, batch)
- `valider-recap` — upsert recap_paie (auth admin)

**Auth :** token applicatif dans le body, vérifié serveur — collab : `collaborateurs.token` ; manager : `equipes.manager_token` ; admin : RPC `verifier_admin`. Acteur collab = non fiable → recalcul serveur. Acteur admin = de confiance → fonctions « fines » (calcul au front).

**Sécurité base** (voir `sql/coupure_ecriture_anon.sql`, appliqué en base le 16/07/2026) : écriture `anon` révoquée sur toutes les tables (SELECT conservé) ; RPC écrivantes et fonctions cron verrouillées en `service_role`/`postgres`. `verifier_admin` reste exécutable par anon (login).

**Workflow Edge :** CC code + commit les fonctions ; Guillaume déploie au Terminal (`supabase functions deploy <nom>` → Supabase, PAS GitHub). `verify_jwt = false` figé par fonction dans `supabase/config.toml`. Preuve de branchement = onglet Network (fonction en 200).

## Méthode de travail
- **Éditions chirurgicales uniquement** : ne jamais réécrire un fichier entier.
- **Une seule modification à la fois** : on discute, on valide, ensuite on code.
- **`BACKLOG.md` est remplacé par `FEUILLE_DE_ROUTE.md` depuis le 12/08/2026** —
  document de suivi unique (correctifs, chantiers ouverts, évolutions, ce qu'il
  ne faut pas changer, méthode).

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

### PROD ACTUELLE (Settings → Pages)

⚠️ **Bascule faite.** GitHub Pages sert désormais la branche **`supabase`** —
mode **« Deploy from a branch »**, dossier **`/ (root)`** : c'est l'appli
Supabase que les collègues utilisent en ce moment.
**`main` n'est PLUS servie** : elle est la **branche de ROLLBACK** (prod
GAS/Sheets intacte, à repointer dans Settings → Pages en cas de problème).
Site live : **https://chantsdelaterre.github.io/suivi-temps/**
(Les sections « bascule du 15 » ci-dessous sont **historiques** — le plan est
exécuté.)

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

## Moteur de paie — règles de calcul (conception)

### Cadre du moteur de PÉRIODE

Pour une période + un collab : (1) prend ses **jours** (saisie brute), (2) résout
le **contrat en vigueur à la date de chaque jour** via `historique_contrats`,
(3) applique les règles ci-dessous, (4) produit les **totaux** (heures
travaillées, heures AT, heures CS, CP ventilés par jour, nb jours travaillés),
(5) **fige le tout** (`paie_detail` + `recap_paie`) à la **validation**.

### Règles par type de jour (VERROUILLÉES)

- **`travaillée`** : heures = somme des créneaux (`total_heures` de la saisie
  collab). Comptées **en heures**.
- **`AT`** (arrêt de travail : maladie, accident) : heures = **valeur saisie par
  l'admin**, **PRÉ-REMPLIE à 7 h**, à **confirmer/corriger SYSTÉMATIQUEMENT, jour
  par jour**. Le 7 h « mâche le travail » dans ~80 % des cas (temps plein, jour
  travaillé) mais **ne dispense jamais de vérifier** — y compris mettre **0 h**
  les jours non travaillés (ex : collab qui ne bosse jamais le mercredi → 3 j AT
  = 7+7+0). Comptées **en heures**.
- **`CS`** (congé spécial : naissance, décès, maternité) : **même règle que
  `AT`** (7 h par défaut, à confirmer, jour par jour). Comptées **en heures**.
- **`CP`** (congé payé) : comptés **en JOURS**, **0 h**. **VENTILÉS PAR JOUR DE
  LA SEMAINE** (lundi/mardi/…/samedi). Règle métier : chaque salarié (temps plein
  **OU** partiel) a droit à **5 occurrences de CHAQUE jour de semaine par an**,
  **NON TRANSFÉRABLES** d'un jour à l'autre (le temps partiel sans mercredi doit
  quand même poser ses 5 mercredis). **Pas de prorata**, pas de « 1,25 j » : le
  quota par jour **rétablit l'équité mécaniquement** et empêche le saucissonnage
  favorable. Le moteur de période se contente de **compter/ventiler les CP du
  mois par `jour_semaine`** (colonne déjà présente dans `jours`).

### Séparation CRUCIALE : moteur de période ≠ compteur annuel de CP

- Le **MOTEUR DE PÉRIODE** (ci-dessus) est **borné à une période**. Simple.
- Le **COMPTEUR ANNUEL DE CP** est un **chantier DISTINCT, plus tard** : cumule
  les CP de **toutes les périodes de l'année**, affiche les **droits restants par
  jour de semaine** (5 − pris), **alerte au dépassement**. Touche à l'**année
  entière** + **reprise de l'existant** (combien pris depuis janvier ?).
  = « **chantier annualisation** », **APRÈS** le moteur de période.

### Questions ouvertes (à trancher plus tard, PAS seul)

- **Quota SAMEDI de CP** : certains travaillent le samedi (mais toujours
  5 jours/sem). Combien de samedis ? Tous les collabs ou seulement ceux du
  samedi ? → **À VOIR AVEC PAULINE ET LES GESTIONNAIRES DE PAIE**.
- **Garde-fou AT/CS temps partiel** : signaler **visuellement** à l'admin les
  AT/CS encore à 7 h **non confirmés** (sujet d'affichage, phase Paie).
- **Distinguer AT/CS « 7 h auto » de « confirmé admin »** : flag
  `heures_confirmees`, OU la validation du collab = « tout vérifié » ?
  (phase Paie).

### Prochain gros morceau : greffe de `historique_contrats`

C'est **LA partie délicate** de l'admin (**pas technique, conceptuelle**) : on
**AJOUTE une logique absente** de l'ancien système (`sauverCollab` GAS n'écrit
que l'**état courant**). Un **changement de contrat** doit : **clôturer
l'ancienne ligne** (poser `date_fin`) + **ouvrir une nouvelle** (`date_debut`,
`date_fin` NULL) + **mettre à jour `collaborateurs`** (état courant) = **un
geste, deux écritures coordonnées**. **QUESTION À TRANCHER** : quels champs
**déclenchent une nouvelle ligne d'historique** (contractuels : heures,
structure, `type_periode`, matricule Silae) vs quels champs se **corrigent sur
place sans historiser** (administratifs : email, équipe) ?

## Onglet Paie & workflow — avancement (cadré le 10/06/2026)

### Moteur `calculerPaiePeriode` (phase 1 — lecture seule)

Calcule par collab, sur une période : `heures_travaillees` (somme des
`total_heures`), `AT`/`CS` pré-remplis **7 h** + `nb_at`/`nb_cs` (**nb de
jours**), `nb_cp`, `nb_jours_travailles`. Résout le **contrat en vigueur** via
`historique_contrats` (contexte + **détection de changement** en cours de
période). **Aucune écriture.** Chiffres **validés** (Guillaume : 48 h / 4 CP sur
`DECAL_2026_06`). Commit `98febd2` (+ SQL d'accès).

### Vue récap Paie (phase 2)

Vue récap **branchée sur le moteur**, tableau **12 colonnes** (CP/AT/CS en
**NB DE JOURS** dans le récap ; les **heures** vivent dans le détail), sélecteur
élargi `gelee` / `cloturee` / `ouverte` (**`ouverte` = TEMPORAIRE**, pour
tester), bandeau **lecture seule**, colonnes centrées. Les **3 tableaux**
(Collaborateurs / Récap / Paie) sont alignés de façon cohérente.

### Workflow paie (conçu, validé)

`jours` (saisie collab, **figée au gel, intouchable**) → **IMPORT dans
`paie_detail`** (au **premier accès admin**, détecté par `paie_detail` vide pour
la période) → l'admin **ajuste / valide** dans `paie_detail` → **CLÔTURE fige
`recap_paie`** → **Pauline recopie à la main dans Silae** (export fichier =
plus tard).

- **Statuts période** : `ouverte` → `gelee` → `cloturee` (PAS de statut
  intermédiaire ; `gelee` = **à traiter par l'admin**). **Réouverture possible**
  (`cloturee` → `gelee`). **Pas d'historique des transitions**, juste
  `recap_paie.date_validation`.
- **Import** : copie **couche 1** (photo fidèle des `jours`) + **couche 2
  pré-remplie** (`type_jour_valide = type_jour`, `heures_valide =
  total_heures` / **7 h** AT·CS / **0** CP, `ajuste_admin = false`). L'unicité
  `(periode_id, collab_id, date_jour)` **protège du double import**.
- **RÈGLE SÉCURITÉ** : un **recalcul ne doit JAMAIS écraser un ajustement admin**
  (`ajuste_admin = true` préservé).
- **Heures sup** : **HORS moteur** (gérées à la main par l'admin, trop
  particulier). **Annualisation** : chantier séparé, plus tard. **Jours fériés** :
  à intégrer dans `jours` plus tard (catégorie absente aujourd'hui).
- **AT / CS** : récap = **nb de jours** ; détail = **heures ajustables**.

### SQL fait en base (tracé dans `sql/`)

- `historique_contrats` : `GRANT` + policy **SELECT** `anon`.
- `paie_detail` : `GRANT` + **3 policies** SELECT / INSERT / UPDATE `anon`.

⚠️ **Lecture/écriture OUVERTES — PHASE DEV**, à **resécuriser avec l'auth admin
POST-15** (écriture sur données de paie = particulièrement sensible).

### Prochaine étape

**Coder la fonction d'import** (phase 3, **première écriture**). **Tester** en
**gelant temporairement `DECAL_2026_06`** — **sans risque** : les collabs
saisissent encore sur **Sheets/GAS**, pas Supabase.

### Ménage en attente

- `grouperParSemaine` (**code mort**).
- `initPaie` (**mort temporaire**).
- Statut **`ouverte`** du sélecteur Paie (**à retirer post-test**).

## Phase 3 paie — import + lecture (cadré le 11/06/2026)

**PHASE 3 TERMINÉE (import + lecture).** Chaîne complète validée : ouverture
d'une période **gelée** → **import auto** → récap **depuis la couche 2**, sans
intervention console.

### Étape A — `importerPaiePeriode(periodeId)` (1ʳᵉ ÉCRITURE du projet)

Copie **couche 1** (photo fidèle des `jours`) + **couche 2 pré-remplie**
(`type_jour_valide = type_jour`, `heures_valide = total_heures` / **7 h** AT·CS /
**0** CP, `ajuste_admin = false`, `date_cloture = null`). **Idempotent** (n'écrit
que si `paie_detail` est vide pour la période). Testé sur `DEC_2026_06`
(**261 lignes**).

### Étape B1 — `calculerPaieDepuisPaieDetail(periodeId)`

L'onglet Paie lit `paie_detail` **COUCHE 2** (`type_jour_valide` /
`heures_valide`) au lieu de `jours`. `chargerPaie` branché dessus. Sélecteur Paie
restreint à **`gelee` + `cloturee`** (retrait du `'ouverte'` temporaire).
Compteur « **X / Y collaborateurs** » ajouté.

### Étape B2 — import auto au premier accès

`chargerPaie` appelle `importerPaiePeriode` **avant** le calcul (idempotent,
message d'erreur si échec). Bandeau = « **Paie en préparation — non validée
(validation / clôture à faire)** ».

### Précisions métier tranchées cette session

- **`CS` = attribut ADMIN uniquement** (les collabs ne saisissent **jamais** de
  CS) → le CS **n'arrive PAS par l'import** ; il est **ajouté par l'admin** dans
  `paie_detail` (couche 2) pendant la validation.
- **`AT`** : le collab saisit le **TYPE** (sans heures, `total_heures = 0`) ;
  c'est l'**admin** qui pose les heures (**7 h** de départ en couche 2,
  ajustables).
- **Statuts période** : `ouverte` → `gelee` → `cloturee`. **Pas de statut
  intermédiaire** (`gelee` = à traiter par l'admin). Import déclenché **au
  premier accès** (`paie_detail` vide), **PAS dans le cron**.
- **Séparation des onglets** : **Récap** = période **OUVERTE** (suivi live depuis
  `jours`) ; **Paie** = période **GELÉE / CLÔTURÉE** (depuis `paie_detail`
  couche 2).

### Prochaines étapes

- **Détail collab Paie** (`ouvrirSaisiesPaie`) lu depuis `paie_detail` (réutiliser
  `fetchJoursCollab` / `renderSaisies`).
- **Écritures admin couche 2** : ajustements `heures_valide` / `type_jour_valide`
  (`ajuste_admin = true`), avec la règle « **un recalcul ne doit JAMAIS écraser un
  ajustement** ». **C'est là que le CS s'ajoute.**
- **Validation → clôture** (fige `recap_paie` + `date_cloture`).

### Ménage en attente (actualisé)

- `calculerPaiePeriode` (**doublon depuis B1**, à retirer).
- `grouperParSemaine` (**mort**), `initPaie` (**mort**).
- **Données de test** dans `paie_detail` pour `DEC_2026_06` (**à purger avant
  mise en service**).
- **Resécurisation RLS post-15** (`historique_contrats` + `paie_detail`).

### État

`DEC_2026_06` **remise en `ouverte`** après les tests (gel temporaire utilisé
pour tester l'import — **sans risque**, collabs encore sur Sheets/GAS).

## Onglet Paie — ajustement & validation (cadré le 13/06/2026)

Commit courant : **`a3d4ca8`** sur `supabase`. Le cycle paie est **complet en
lecture/écriture sur Supabase** (hors clôture/PDF).

### FAIT

- **Détail Paie lit `paie_detail` couche 2** (`type_jour_valide`/`heures_valide`)
  via `ouvrirSaisiesPaie`/`renderSaisiesPaie`/`buildTableSaisies`. **Consultation
  = lecture seule** (Type, créneaux, Total, Commentaire verrouillés hors mode
  Modification). **Badge = statut de la période** (`poserBadgePaie`).
- **Ajustement admin** (mode Modification) : **bascule de type**
  (`travaillée`/`CP`/`AT`/`CS`) ; **case Total éditable pour AT/CS** (pré-remplie
  **7** si vide) ; **total recalculé depuis les créneaux** pour `travaillée` ;
  **créneaux vides** pour AT/CP/CS ; **restauration des créneaux d'origine** au
  retour vers `travaillée` (depuis le modèle, couche 1). Piloté par
  `majTotalPaie` selon le type courant, **sans re-render**.
- **Écriture couche 2** : `UPDATE paie_detail` (`type_jour_valide`,
  `heures_valide`, `ajuste_admin=true`) **UNIQUEMENT sur les lignes réellement
  modifiées** (comparaison de **nombres arrondis 2 déc.** des deux côtés).
  **Jamais la table `jours`** (couche 1 = trace intouchable). `date_ajuste_admin`
  **écrit par l'Edge `ajuster-paie` depuis le 09/08/2026** (jamais par le front —
  valeur posée côté serveur). Les ajustements **antérieurs restent NULL** et ne sont
  **pas reconstituables** → « Modif admin » sans date à l'écran (~113 lignes).
- **Bouton unique « 💾 Enregistrer et valider le relevé »** (`enregistrerEtValider`) :
  enchaîne **UPDATE `paie_detail`** → recalcul des totaux → **upsert `recap_paie`**
  (cœur partagé **`upsertRecapPaieCourant`**, sans alert). Après succès → **retour
  à la liste Paie** (`retourPaie`). Un seul feedback.
- **Liste Paie** : colonnes **Validation** (« ✅ Validé » si
  `recap_paie.statut_validation='valide'`) et **Note admin** lues depuis
  `recap_paie` (1 requête par période, injectée dans `calculerPaieDepuisPaieDetail`).

### RESTE (backlog paie, par ordre)

1. **Clôture de période** (`gelee → cloturee`) quand tous les collabs sont validés.
2. **Cycle rouvrir** (`cloturee → gelee`).
3. **Export PDF** du relevé détaillé.
4. **Colonnes `nb_at` / `nb_cs`** à ajouter dans `recap_paie` (récap les ignore
   aujourd'hui ; seules les heures AT/CS y sont).
5. **Ménage** : `rechargerDetailPaie` devenue **inutilisée** ; + doublon
   `calculerPaiePeriode`, `grouperParSemaine`, `initPaie`, fonctions GAS mortes.
6. **RESÉCURISATION RLS post-15** : `paie_detail`, `recap_paie`,
   `historique_contrats` sont en **accès `anon` ouvert (phase DEV)** — à
   restreindre à l'auth admin avant mise en production.

- Cosmétique / couche 2 : le front écrit '' (chaîne vide) là où la couche 1 a
  null pour un créneau absent (le `|| ''` dans enregistrerEtValider). Sans effet
  fonctionnel (fmtHeure('') === '' → créneau non affiché, modale et relevé), mais
  ces lignes ressortent à tort dans une comparaison `c1_debut is distinct from
  c1_debut_valide`. Constaté sur COLL016 / 2026-05-19 (c3).

### Accès SQL ouverts en base (phase DEV, le 13/06)

- **`recap_paie`** : `grant select, insert, update … to anon` + policies
  lecture/insertion/maj (`using/with check (true)`). Consigné dans
  `sql/recap_paie.sql`.
- **`paie_detail`** : colonne **`date_ajuste_admin`** (`timestamptz`, nullable)
  ajoutée par `ALTER TABLE` — **écrite par l'Edge `ajuster-paie` depuis le
  09/08/2026** (jamais par le front). Ajustements antérieurs = NULL, non
  reconstituables. Consignée dans `sql/paie_detail.sql`.

## Onglet Paie refondu + PDF + état réel (cadré le 14/06/2026)

Commit courant : **`7ca3484`** sur `supabase` (poussé). Cette section **fait
foi** sur les points qu'elle recouvre (supersède le backlog du 13/06 : la
**clôture est faite**, le **bouton Rouvrir est abandonné**).

### ÉTAT ACTUEL (fait, sur `supabase`)

- **Onglet Paie refondu en 2 sous-onglets** : **« À traiter »** (périodes
  `gelee`) / **« Clôturées »** (périodes `cloturee`). Le sélecteur déroulant
  unique a disparu.
  - **À traiter** : en-tête listant les périodes gelées avec indicateur
    **« X/Y validés »** (vert si X===Y) + **bouton Clôturer** — actif seulement
    si **X===Y**, avec **re-vérif fraîche** au clic, puis `UPDATE periodes`
    `statut` **gelee→cloturee**. X/Y calculés en **2 requêtes batch**
    (`recap_paie` pour X validés, `paie_detail` pour Y = collabs avec données).
  - **Clôturées** : **table transversale filtrable** (`recap_paie` × périodes
    clôturées), **3 filtres** (structure / collaborateur / période, combinés
    **en mémoire**), **structure croisée depuis `collaborateurs`** (pas figée
    dans `recap_paie`), colonnes **AT/CS en « Xh/Yj »**. **Bouton Détail**
    (ouvre le relevé du collab pour cette période ; **re-validation possible**).
    **Bouton PDF** (relevé d'heures imprimable).
- **`recap_paie`** : colonnes **`nb_at`** et **`nb_cs`** (nb de **jours** AT/CS)
  ajoutées et **écrites par `upsertRecapPaieCourant`** à la validation.
- **PDF relevé d'heures collab** (`genererPdfReleve`) : **impression navigateur**
  (`window.print`), mise en page **A4**, lit **`paie_detail`**, **total semaine
  recalculé à la volée** (reset lundi, **jamais `total_hebdo_prog`**), mapping
  **structure→société** : `SCEA`/`SAS` → « … Chants de la Terre », `SARL` →
  « SARL Les 6 Saveurs ». Fonds week-end + badges forcés à l'impression
  (`print-color-adjust:exact`).
- **`historique_contrats`** : **29 lignes** (18 anciens `COLL001`-`018` + 12
  nouveaux `COLL019`-`030` comblés ce jour ; `TEST001` exclu). Toutes
  `date_debut = 2026-01-01`, `date_fin = null`.

### POINTS IMPORTANTS / DETTE

- **`sauverCollab` écrit UNIQUEMENT dans `collaborateurs`, JAMAIS dans
  `historique_contrats`.** L'**historisation automatique** (geste à 2 écritures :
  clôturer l'ancienne ligne + ouvrir une nouvelle quand un champ **contractuel**
  change) **n'est PAS implémentée** = **prochain gros morceau conceptuel**
  (cf. « greffe de `historique_contrats` »).
- **Écriture `anon` ouverte** sur `collaborateurs`, `periodes`, `recap_paie`,
  `jours`, `paie_detail`, `historique_contrats` = **phase DEV non sécurisée**.
  **Resécurisation RLS = chantier post-bascule prioritaire.**

### BACKLOG

- **Bug** : à la saisie d'un jour `CP`/`AT`/`CS`, **vider les créneaux**
  (présent dans **`index.html` ET `admin-v2.html`**).
- **PDF 2 (récap admin)** : contexte contrat, matricule Silae, date de
  validation — **dépend en partie de l'historisation**.
- **Indicateur de modification de contrat** sur le récap (badge « ! » + modale
  avant/après) — **dépend de l'historisation branchée**.
- **Ménage code mort** : `calculerPaiePeriode`, `grouperParSemaine`, `initPaie`,
  `toggleValidation`, `sauverNote` (`peuplerSelecteurPaie` déjà retirée).
- **ABANDONNÉ** : **verrou lecture seule période clôturée** + **bouton Rouvrir**.
  Décision : on **rouvre 1 collab via Détail** (re-validation), la **période
  reste `cloturee`**. (Supersède les points 1-2 « rouvrir » du backlog du 13/06.)

## Chantier HISTORISATION DES CONTRATS — conception figée (14/06/2026)

> À coder **à froid, en session dédiée**. Chantier **sensible** : on écrit dans
> `historique_contrats`, table **lue par le calcul de paie**. Une erreur fausse
> des calculs de paie. Procéder **par étapes testables**, comme la clôture.

### Principe métier

Un champ **contractuel** ne change jamais « en écrasant » : on garde la trace.
**Geste à deux écritures coordonnées** :
1. **Clôturer** la ligne d'historique en cours → `date_fin` = **veille de la date d'effet**.
2. **Ouvrir** une nouvelle ligne → `date_debut` = date d'effet, `date_fin` = null, nouvelles valeurs.

- Champs **contractuels** (déclenchent une nouvelle ligne) : `heures_hebdo`,
  `structure`, `type_contrat`, `type_periode`, `matricule_silae`.
- Champs **non contractuels** (ne touchent JAMAIS l'historique) : équipe, email,
  nom, etc. (« administratif »).
- **Règle d'or** : les champs contractuels ne sont JAMAIS modifiables librement —
  ils ne changent QUE par le geste daté « changement de contrat », qui crée
  toujours la trace historique correspondante.

### Les 3 écrans

1. **Formulaire de CRÉATION (l'actuel, conservé)** : tous les champs saisis (dont
   contractuels). À la validation → crée la ligne `collaborateurs` **ET** la 1re
   ligne `historique_contrats` (`date_debut` = **date d'activation du collab**,
   `date_fin` = null). Seul ajout vs aujourd'hui : la création écrit aussi
   l'historique.
2. **Modale unique « Modifier collab » (existant) — DEUX zones / DEUX boutons** :
   - **Haut — admin éditable** (nom, email, équipe…) : bouton « Enregistrer » →
     met à jour `collaborateurs` **uniquement**, ne touche pas l'historique.
   - **Bas — contrat / historique** : situation contractuelle **actuelle** en
     **lecture seule** ; zone « changement de contrat » = les 5 champs
     contractuels + **date d'effet** ; **bouton séparé** « Enregistrer le
     changement de contrat ». Deux gestes de nature différente, **deux mécaniques
     distinctes**.

### Règles de date d'effet

- Date d'effet **présente ou future** : cas normal, autorisé.
- Date d'effet **rétroactive sur une période déjà clôturée** : **avertir / bloquer**
  (pas de recalcul d'une paie déjà validée). Régularisation rétroactive = cas
  avancé, traité plus tard.

### Technique : geste à deux écritures = fonction SQL TRANSACTIONNELLE

Le changement de contrat fait **3 écritures** (fermer ancienne ligne + ouvrir
nouvelle + maj `collaborateurs`) → une **fonction SQL transactionnelle**
(tout-ou-rien), même esprit que `verifier_admin`. **JAMAIS** un enchaînement de
requêtes côté front pour ce geste.

### Préalable au code (état des lieux en début de session)

- Comment `sauverCollab` gère **création vs édition** aujourd'hui (champs,
  formulaire HTML) pour savoir comment le **scinder** : création (geste 1 +
  écriture historique) vs édition (modale 2 zones).
- Structure de `historique_contrats` (connue) : `collab_id, date_debut,
  date_fin, structure, type_contrat, heures_hebdo, matricule_silae, type_periode`.

### Ce que ça débloque ensuite

- **PDF 2 (récap admin)** : situation contrat au 1er jour de période /
  modifications / situation au dernier jour (ou « pas de modification »). Ne
  fonctionne vraiment qu'avec un historique vivant → **après ce chantier**.
- **Indicateur de modification de contrat** sur le récap (badge « ! » + modale
  avant/après).

### État de départ (au 14/06/2026)

- `historique_contrats` : **29 lignes**, toutes `date_debut=2026-01-01`,
  `date_fin=null`, **une seule ligne par collab**.
- `sauverCollab` écrit **UNIQUEMENT** dans `collaborateurs`, jamais dans
  `historique_contrats` → c'est ce qu'on vient corriger.
- `matricule_silae` : **null partout** (à renseigner un jour ; non bloquant).

## Historisation des contrats — MODÈLE JOURNAL (cadré le 28/06/2026)

⚠️ Cette section FAIT ÉVOLUER la vision « geste à deux écritures » décrite plus haut (section « greffe de historique_contrats »). Le modèle retenu est désormais un JOURNAL append-only.

### Principe
- `historique_contrats` = journal : on AJOUTE des lignes, on n'écrase jamais.
- Chaque ligne : valeurs contractuelles + dates [date_debut, date_fin] + created_at (horodatage) + cree_par (auteur : Pauline / Guillaume / Elsa).
- Le contrat ACTUEL se CALCULE, il ne se stocke pas comme un état figé.

### Règle « contrat en vigueur aujourd'hui »
La ligne où date_debut <= aujourd'hui ET (date_fin IS NULL OU date_fin >= aujourd'hui).
- Si plusieurs (chevauchement) → la plus récente par created_at gagne.
- Si aucune (trou) → pas de contrat ce jour-là (les trous sont OK).
- Effet FUTUR autorisé (préparer un contrat à l'avance, ex. TESA→CDI de Jonas).
- 3 états déduits des dates (jamais stockés) : passé (terminé) / présent (actuel) / futur (à venir).

### Fiche collaborateurs = cache (OPTION 2 retenue)
La fiche reste le statut courant. Un CRON QUOTIDIEN la met à jour avec le contrat en vigueur ce jour-là (bascule auto quand un contrat futur prend effet). Donc ajouter_contrat ne doit PAS mettre à jour la fiche immédiatement pour un effet futur.

### Affichage : timeline
Zone Contrat de la modale édition = toutes les lignes du collab, ordonnées, colorées selon passé/présent/futur. Bouton « + Nouvel événement » (Fin de contrat / Nouveau contrat) avec date d'effet + note + auteur.

### Déjà en prod (mais à retoucher pour ce modèle)
- Étape 1 : création écrit la 1re ligne (commit a19b032). OK.
- cloturer_contrat (pose date_fin) — OK, en prod (79b38ea).
- ajouter_contrat — à RETOUCHER (maj fiche immédiate ne convient plus ; garde-fou anti-chevauchement à revoir car chevauchement autorisé).
- Front 2a (zone Contrat) : affichage « Aucun contrat en cours » FAUX (confond fin future et passée) → à REMPLACER par la timeline.

### Décisions ABANDONNÉES (ne pas re-dériver)
- Contrainte d'exclusion stricte anti-chevauchement → abandonnée (résolution par created_at).
- « Modif données contrat » comme geste séparé → abandonnée (tout passe par fin/nouveau).

Détail complet : plan_modele_journal_contrats.md (note de conception du 28/06).

## Multi-tenant (horizon — garder la porte ouverte, ne PAS implémenter maintenant)

L'appli vise à terme une architecture SaaS multi-tenant : une seule appli + une
seule base, isolation logique par `organization_id` + policies RLS Postgres (PAS
une copie par client). Détail complet : NOTE_Mes_Heures_Pro_commercialisation.md.

⚠️ Principe à respecter dès maintenant, SANS coder le multi-tenant :
- **Ne pas l'implémenter** tant que l'appli n'est pas finie et sécurisée pour Chants
  de la Terre (un seul client). C'est un chantier d'APRÈS.
- **Mais éviter les choix qui le rendraient coûteux** : pour toute nouvelle fonction
  touchant la SÉCURITÉ ou l'ACCÈS aux données (Edge Function, policies RLS,
  authentification), la concevoir de façon à ce qu'ajouter un filtre
  `organization_id` plus tard soit SIMPLE (un filtre en plus), pas une refonte.
- **La logique métier n'est PAS concernée** (calculs d'heures, modèle journal des
  contrats, moteur de paie, timeline, UI) : elle restera compatible, on ajoutera
  juste un filtrage par organisation par-dessus. Donc on code normalement, sans
  sur-ingénierer.
- Le multi-tenant repose sur la migration Supabase déjà engagée (Sheets ne
  permettait pas l'isolation). L'isolation se pose en FONDATION (au moment de
  l'Edge Function / RLS), elle ne se rajoute pas après — une seule "serrure" mal
  posée = fuite de données entre clients.

## À AMÉLIORER — UX de l'activation programmée (piège identifié le 01/07/2026)

Problème constaté : poser une `date_activation` (même à aujourd'hui) sur un collab
au statut `inactif` ne l'active PAS. Le cron `activer_collabs_en_attente` ne bascule
que les collabs au statut `en_attente` → `actif`. Un `inactif` avec date_activation
reste inactif (donc pas de génération de jours). Cas réel : Sati GUNDUZ (COLL019)
n'a pas eu son jour du 01/07, rattrapée à la main (activation manuelle + relance de
generer_jour_aujourdhui, idempotente).

Comportement actuel (à connaître) :
- date_activation SEULE ne déclenche rien. Il faut le statut `en_attente` pour que
  le cron active au jour dit, OU activer à la main (actif=true, statut=actif).
- C'est contre-intuitif (on croit que « mettre une date d'activation » suffit).

Pistes d'amélioration (à concevoir plus tard, pas urgent) :
- Que poser une date_activation FUTURE bascule automatiquement le collab en
  `en_attente` (au lieu de le laisser inactif).
- OU un message clair dans la modale expliquant la différence inactif / en_attente.
- OU un bouton admin « générer le jour manquant » pour rattraper une activation
  tardive sans passer par le SQL (déjà évoqué au backlog).

## Fonctionnalités livrées (07/07/2026)

- **Fiche collaborateur** : timeline des contrats (modèle journal), en-tête identité compact + zone Contrats, champ téléphone, type CDD.
- **Filtres par type de contrat** (CDI/TESA/CDD) sur onglets Collaborateurs et Récap.
- **PDF collab "Mes saisies — dernière période complète"** (index.html, fonction genererPdfMesSaisies) : bouton dans #vue-mesjours → génère un PDF A4 paysage des saisies BRUTES (table jours, pas paie_detail) de la dernière période clôturée du collab. Jours non saisis (pas CP/AT et 0h) affichés vides. Pattern window.open + window.print(), pas de lib. But : confronter au RIH.

## Chantiers à venir (notés)
- Démarrer un PROCESSUS.md (règles métier + processus, au fil de l'eau).
- Inventaire Edge Function (lecture seule) avant migration sécurité.
- Onboarding collaborateur & fiche RH étendue → voir CADRAGE_onboarding.md

## Contrats & dossiers — modèle CONSOLIDÉ (17/07/2026)

> 🔎 **L'état du CODE se constate avec Claude Code (grep sur le dépôt réel),
> JAMAIS depuis le chat** — les fichiers projet vus en chat sont une copie FIGÉE,
> potentiellement périmée. CLAUDE.md porte les **DÉCISIONS** (le pourquoi), pas
> l'état du code (le quoi). **Aucun numéro de ligne dans ce fichier** : il serait
> périmé dès le commit suivant.

> Cette section FAIT FOI et SUPERSÈDE les sections « HISTORISATION DES
> CONTRATS — conception figée (14/06/2026) » et « Historisation des
> contrats — MODÈLE JOURNAL (28/06/2026) » sur tous les points qu'elle
> recouvre.

### Les 3 règles

1. Un dossier = une démarche en cours.
2. Le dossier meurt en donnant un contrat.
3. Rien d'hypothétique dans le moteur de paie.

### Séparation des natures de données

- `collaborateurs` = QUI (administratif, état courant).
- `historique_contrats` = LE FAIT JURIDIQUE, daté. Journal append-only.
  Lu par la paie. Une ligne n'apparaît QU'À LA SIGNATURE.
- `dossiers` (à créer, chantier séparé) = L'INTENTION. Dates prévues,
  statut de la démarche, tâches (DPAE, contrat, FDP, signature).
  Physiquement AILLEURS : une donnée hypothétique dans une autre table
  ne peut pas être lue par erreur par la paie. Jamais un champ
  « statut : prévu » dans historique_contrats.

### Une fiche = une personne + UN employeur

Un collaborateur qui travaille dans 2 structures a 2 fiches (cas réels :
Eric BOEHM = SAS + 6 Saveurs, Alice HAGER = TESA SAS + CDI SARL). Ce
n'est PAS un bricolage : en paie française, 1 contrat dans 1 structure
= 1 matricule Silae, 1 DPAE, 1 bulletin. Le modèle épouse le réel.

Conséquences :
- `jour_id = collab_id_date` tient (2 fiches = 2 jours le même samedi).
- Pas de `contrat_id` sur les jours.
- Le cache de la fiche reste possible (1 fiche = 1 contrat en vigueur).
- Dette assumée : les données de personne (RIB, carte vitale) sont en
  double sur les 2 fiches. Un `personne_id` viendra plus tard si le
  nombre de cas grandit. Aujourd'hui : 2 cas sur ~50 → on note, on
  n'implémente pas.

### Le garde-fou anti-chevauchement est CONSERVÉ

⚠️ SUPERSÈDE la note du 28/06 qui disait « à revoir car chevauchement
autorisé ». Le chevauchement était censé couvrir le multi-structure ;
le multi-structure passe par des fiches séparées. Donc dans une fiche,
2 contrats qui se recouvrent = ERREUR DE SAISIE. Le garde-fou de
`ajouter_contrat` reste. La résolution « le plus récent par created_at
gagne » est ABANDONNÉE : elle masquerait un bug.

### Pas de détection automatique de changement de champ

⚠️ SUPERSÈDE le point 2 du backlog du 14/06. Les champs contractuels ne
sont PAS modifiables dans la fiche et sauverCollab ne détecte RIEN.
Ils ne changent QUE par un geste explicite et daté. Sinon, corriger une
faute de frappe dans « TESA » déclencherait un changement de contrat.

### Deux gestes, pas un

Un contrat s'arrête = un événement. Un autre démarre = un autre
événement. Pas de `changer_contrat` atomique : il fabriquerait un
événement composite qui n'existe pas dans le réel, et rendrait
impossible le trou (qui est un fait). Le filet de sécurité n'est pas la
transaction, c'est la timeline qui montre l'état.

### Le cache de la fiche : GARDÉ, mais réparé (option A1)

`generer_jour_aujourdhui()` lit `collaborateurs.type_periode`, pas le
journal. C'est un cache. Décision : le garder (le supprimer toucherait
la génération des jours + tout le front qui lit ces colonnes).

État réel constaté le 17/07 (grep + pg_proc) :
- `ajouter_contrat` EXISTE en base mais N'EST APPELÉE PAR AUCUN FRONT.
  Elle fait un `update collaborateurs` INCONDITIONNEL → un contrat à
  effet futur met la fiche à jour DÈS LA SAISIE (trop tôt).
- `cloturer_contrat` ne touche PAS la fiche (asymétrie avec la
  précédente).
- Dans le **SQL versionné du dépôt** (`sql/trigger_quotidien.sql`),
  `trigger_quotidien` enchaîne 4 étapes (activer_collabs_en_attente →
  ouvrir_geler_periodes → generer_periodes_suivantes → generer_jour_aujourdhui) et
  **aucune ne lit `historique_contrats`**. ⚠️ Le dépôt reflète le fichier de
  référence, PAS forcément l'état exact de la base (à confirmer côté base si un
  doute). Aucun cron de rafraîchissement de fiche n'existe dans `sql/`.

À faire (chantier séparé) : une fonction unique
`rafraichir_fiche_collab(p_collab_id)` portant la règle « contrat en
vigueur aujourd'hui », appelée par 3 endroits :
- `ajouter_contrat` (remplace l'update inconditionnel)
- `cloturer_contrat` (corrige l'asymétrie)
- `trigger_quotidien` en ÉTAPE 3,5 — APRÈS `generer_periodes_suivantes`,
  AVANT `generer_jour_aujourdhui`. L'ordre est CRITIQUE : après, le jour
  est déjà créé dans la mauvaise période et `ON CONFLICT DO NOTHING` ne
  le corrigera jamais.

Le trou (aucun contrat en vigueur) : le rafraîchissement NE TOUCHE À
RIEN (la fiche garde l'ancienne valeur, le collab continue de saisir) et
le trou est signalé dans le rapport texte de `trigger_quotidien`. On ne
bloque pas la saisie pour punir une saisie admin en retard.

### La timeline (LIVRÉE — commit 31186c7)

`chargerContratActuel()` (`admin-v2.html`) est **déjà une timeline lecture seule**
de TOUTES les lignes de contrat du collab (aucun bug résiduel ; l'ancien
`.is('date_fin', null).maybeSingle()` n'existe plus). Comportement réel constaté
dans le code :
- Elle lit `historique_contrats` filtré par `collab_id`, **ordonné par `date_debut`
  croissant** (la plus ancienne en haut).
- L'état de chaque ligne est **calculé** (jamais stocké) par comparaison de chaînes
  `YYYY-MM-DD` à aujourd'hui : **passé/terminé** (`date_fin` connue < aujourd'hui,
  fond gris) ; **à venir** (`date_debut` > aujourd'hui, fond bleu, « À partir du … »).
- ⚠️ Pour un contrat **en cours**, l'affichage DIFFÈRE selon la date de fin : **avec
  date de fin connue** (cas TESA) → fond orange, « … se termine le … » ; **sans date
  de fin** → fond vert, « Depuis le … ». Le bouton « Fin de contrat » n'apparaît que
  sur une ligne en cours **sans date de fin** (cohérent avec `cloturer_contrat` qui
  cible `where date_fin is null`).

Les TROUS NE SONT PAS AFFICHÉS : un trou est ambigu (fin définitive ? pause
saisonnière ? attente d'un CDI ?) et le journal ne sait pas lequel. L'incertitude
appartient au dossier, pas au journal.

### Manques identifiés (non traités, notés)

- `ajouter_contrat` et `creer_collaborateur_avec_contrat` n'ont PAS de
  paramètre `date_fin` (écrit en dur à null) → aucun TESA ne peut naître
  avec sa date de fin, alors qu'un TESA est un contrat à terme connu à
  la signature. Conséquence : l'alerte J-5 « fin de contrat » ne pourra
  jamais se déclencher tant que ce n'est pas corrigé.
- Le TAUX HORAIRE n'existe nulle part dans l'appli (le tableau TESA le
  porte : 9,85 à 16 €). Donnée contractuelle et datée → sa place serait
  dans le journal. À décider : dans l'appli ou chez Silae ?
- `heures_hebdo` : 6 Saveurs raisonne en MENSUEL, pas en hebdo.
- `cree_par` et `note` : prévus par la note du 28/06, jamais créés.
- `creer_collaborateur_avec_contrat` fait `date_debut = p_date_activation`
  et `historique_contrats.date_debut` est NOT NULL → créer un collab
  sans date d'activation fait planter la création. Bloquant pour le
  chantier « prospect ».

### Constats de code re-vérifiés par grep (17/07)

> Le titre précédent « Vérifié le 17/07 (grep) » reposait sur une copie PÉRIMÉE
> d'`admin-v2.html`. Constats refaits par grep sur le dépôt réel :

- **Drum picker** (`index.html`) : **présent** (`#drum-h`/`#drum-m`, `initDrums`).
- **Vidage des créneaux sur CP/AT/CS** : `index.html` le fait via `isAbsence`
  (`['CP','AT','CS']` → créneaux vidés). `admin-v2.html` **ne contient PAS**
  d'`isAbsence` : la gestion CP/AT/CS y passe par un autre mécanisme (les créneaux
  ne sont capturés que pour `travaillée`). Cohérence fonctionnelle **à vérifier**
  (non tranchée par grep).
- **Code mort** (défini, **aucun site d'appel trouvé par grep**) :
  `grouperParSemaine`, `initPaie`, `sauverNote`, `rechargerDetailPaie`,
  **`calculerPaiePeriode`** (seule autre occurrence = un commentaire) et
  **`toggleValidation`** — ⚠️ à NE PAS confondre avec `toggleValidationModal`,
  qui, lui, est appelé (`onclick` du bouton « Valider »).
- **Vivant, NE PAS supprimer** : `toggleCollab` (appelé via `onclick`) et
  `toggleValidationModal`.

## Import paie & lectures Supabase — décisions du LOT 1 (30/07/2026)

### 1. Pagination des lectures — helper `fetchAllPages`
- Le **« Max rows » du projet est à 1000** : toute lecture non bornée **tronque
  SILENCIEUSEMENT**. Toute nouvelle lecture susceptible de dépasser 1000 lignes
  **doit** passer par le helper.
- **pageSize = 500** (et non 1000) : à pageSize égal au plafond serveur, la
  condition d'arrêt `data.length < pageSize` deviendrait un **faux signal de fin**
  si le plafond descendait. 500 garde une marge franche.
- **MAX_PAGES = 400** : filet contre une pagination qui **ne progresse pas**, PAS
  une limite de volume métier. Un seuil trop bas produit une erreur → Y=0 →
  clôture impossible **sans message**.
- **Tri stable obligatoire, sur une colonne PROUVÉE** : `jour_id` pour `jours`
  (aucune colonne `id` prouvable — pas de `CREATE TABLE` versionné), `id` pour
  `paie_detail` et `recap_paie`.

### 2. Import paie DIFFÉRENTIEL (remplace l'idempotence par comptage)
- L'ancienne garde `count > 0 → skip` était au niveau **PÉRIODE** : une seule
  ligne écrite dans `paie_detail` avant le gel **neutralisait l'import de TOUTE la
  période**, et la clôture globale passait **silencieusement** avec des collabs
  manquants (`X === Y` satisfait sur une poignée de collabs).
- Remplacée par un **différentiel sur (collab_id, date_jour)** + **upsert
  `ignoreDuplicates`** sur l'unique `(periode_id, collab_id, date_jour)`.
- **Conséquence architecturale** : « un recalcul n'écrase jamais un ajustement
  admin » devient une **propriété du SCHÉMA**, plus une convention.
- **Contrepartie à retenir** : une ligne importée n'est **PLUS JAMAIS rafraîchie
  depuis `jours`**. On n'importe donc que des jours **DÉFINITIFS** — soit période
  gelée, soit jours d'un collab bornés jusqu'à sa date de fin. **Ne jamais
  déclencher un import sur une période ouverte en cours de saisie.**

### 3. Envoi par lots de 500 vers les Edge Functions
- **Aucune limite de taille de corps** de requête publiée par Supabase, **MAIS
  2 s de temps CPU maximum par invocation** (hors I/O). Le parsing JSON et la
  boucle de whitelist sont du **CPU pur**. **Découper reste la règle** pour tout
  envoi volumineux.

### 4. Ordre de déploiement Edge / front — NON COMMUTATIF
- **Edge d'abord, front ensuite.** L'inverse (front avant Edge) donne un état où
  **plus AUCUNE ligne ne s'importe jamais, sans erreur visible**. À retenir pour
  tout futur changement touchant les deux côtés.

## Clôture partielle de paie par collaborateur — décisions du LOT 2 (testé, 09/08/2026)

> Chantier : figer la paie d'UN collaborateur en fin de contrat, borné à une date,
> sur une période encore OUVERTE — sans attendre le gel de la période, pour sortir
> son RIH tout de suite.

### 1. Clôture partielle : une BORNE, pas un statut
- `recap_paie.date_fin_validation` (date, nullable). **NULL = validation normale ;
  renseignée = validée jusqu'à cette date INCLUSE.**
- `statut_validation` reste `'valide'` : `calculerCountsPaie` et `cloturerPeriode`
  sont **inchangés**. Le collab borné compte dans X **comme** dans Y et **ne bloque
  pas** la clôture globale.
- Le collab borné **n'est PAS désactivé** par le chantier. La désactivation reste un
  **geste manuel** (règle : désactiver si aucune ligne de `historique_contrats` n'a
  `date_fin` nulle ou ≥ aujourd'hui).

### 2. Le déclencheur est `historique_contrats`, pas une décision admin
- Le geste naît d'une **date de fin posée sur le contrat**, pas d'une intention de
  clôturer. La date est donc **HÉRITÉE du contrat**, ce qui élimine presque
  entièrement le risque de **borne trop longue** — le seul coûteux, puisque l'import
  différentiel **ajoute sans jamais supprimer**.
- RPC `candidats_cloture_anticipee()` : `DISTINCT ON (collab_id)` trié par
  `date_debut DESC, date_fin DESC`. Retenir la **ligne de contrat la plus récente**
  rend la condition « aucun contrat suivant » vraie **PAR CONSTRUCTION** — pas de
  requête supplémentaire.
- `date_fin DESC` en second critère : à `date_debut` égale, **NULL d'abord** en
  Postgres → un contrat **ouvert** l'emporte sur un contrat clos. **Dans le doute,
  on ne déclare personne parti.**
- Périmètre volontairement **étroit : les DÉPARTS seulement.** Un changement de
  contrat en cours de période (« Jonas puissance deux ») reste **hors chantier**.
- Le bloc **ne filtre JAMAIS sur `actif`** : il se construit depuis
  `historique_contrats`. Sinon la désactivation **masquerait exactement le travail
  qu'elle vient de créer**.

### 3. Le garde-fou vit dans `importerPaiePeriode`, pas dans le chemin
- Un import de période **ENTIÈRE** sur une période **OUVERTE** est **refusé** (retour
  `ok:true, importe:false, message:'periode ouverte'` — surtout **PAS une erreur**,
  qui masquerait tout l'écran). L'import **BORNÉ** d'un seul collab reste autorisé.
- **Pourquoi là et pas dans une variable de contexte** : `retourPaie` appelle
  `chargerPaie`, et `enregistrerEtValider` se termine **par** `retourPaie`. Le chemin
  du **SUCCÈS** déclenchait donc l'import de toute la période. Une garde posée **dans
  la fonction** couvre **tous les appelants**, y compris ceux qu'on n'a pas imaginés.
- La règle du lot 1 (« on n'importe que des jours **définitifs** ») cesse d'être une
  convention pour devenir une **propriété du code**.

### 4. La borne se PRÉSERVE par omission, jamais par null
- `valider-recap` filtre par `if (k in recap)` et fait un upsert **sans**
  `ignoreDuplicates` : une clé **ABSENTE** du body n'entre pas dans le `SET`, donc la
  valeur en base est **préservée**. Un `null` **EXPLICITE l'effacerait**.
- Règle : on envoie `date_fin_validation` **seulement pour POSER ou ALLONGER** une
  borne. Validation normale ou re-validation d'un collab déjà borné → on **OMET** la
  clé.
- **Vérifié en conditions réelles**, pas déduit.

### 5. `importer-paie` écarte les jours post-borne — dernière barrière
- L'Edge **lit `recap_paie`**, récupère les bornes non nulles, **filtre avant
  l'upsert**. Le front **ne peut pas** s'en charger : son différentiel compare à ce
  qui est **DÉJÀ** dans `paie_detail`, or les jours post-borne **n'y sont justement
  pas encore**.
- Échec de lecture des bornes → **500, on n'importe PAS « au cas où »**. Une borne
  ignorée produit un **dégât silencieux et irréversible**.
- Comparaison sur les **10 premiers caractères ISO** (`YYYY-MM-DD`) : l'ordre
  lexicographique coïncide avec l'ordre chronologique — aucune conversion, aucun
  fuseau.

### 6. Un collab SANS saisie doit pouvoir être clos
- `calculerPaieDepuisPaieDetail` part de `paie_detail` : un collab sans ligne est
  **ABSENT** du tableau, donc **introuvable à l'upsert**.
- Une **entrée à zéro** est fabriquée, et **REPOSÉE après** le recalcul
  d'`enregistrerEtValider` qui l'écraserait sinon.
- **Décision métier** : un relevé vide est un **document valide** — il atteste
  qu'aucune heure n'a été faite. Le **PDF se génère aussi sans lignes**.

### 7. Le sous-onglet « Clôturées » montre les RELEVÉS FIGÉS
- Il lit désormais les **périodes clôturées ET toute ligne portant une borne**, quel
  que soit le statut de sa période. Sans quoi un collab borné **disparaît** du bloc
  « Clôtures anticipées » **sans entrer nulle part ailleurs** — invisible, donc pas
  de RIH, ce qui est le **BUT** du chantier.
- Le **early-return « aucune période clôturée » a dû être levé** : le cas nominal est
  justement une borne **alors qu'aucune période n'est encore clôturée**.

### 8. Pas de cache sur la liste des candidats
- **Un appel Edge par re-rendu** de l'en-tête « À traiter ». C'est **NÉCESSAIRE**,
  pas un oubli : le bloc doit se reconstruire **sans le candidat traité** après
  validation. Un cache le laisserait affiché et l'admin **cliquerait deux fois**. **Ne
  pas « optimiser ».**

### 9. Méthode : un diff MONTRÉ n'est pas un diff APPLIQUÉ
- **Incident réel** : plusieurs tours de recette sur du code **qui n'existait pas**,
  puis **124 lignes importées en prod sur une période ouverte**.
- Tout prompt de modification se termine désormais par « **montre-moi la ligne telle
  qu'elle est DÉSORMAIS dans le fichier et confirme que le fichier EST modifié** ».
- **Réflexe de recette** : `<fonction>.toString().includes('<marqueur>')` **avant tout
  test**, pour savoir quelle version est chargée.
- Et : toute recette en console se fait **sur localhost, jamais sur la prod**.

### 10. Demander à CC de PROPOSER avant d'écrire, sur les points sensibles
- Deux pièges évités ainsi : la **contradiction** entre l'entrée fabriquée et le
  recalcul d'`enregistrerEtValider`, et le fait que `nomPeriode` se **résolvait depuis
  les seules périodes clôturées**.
- À faire **chaque fois qu'un diff touche une fonction partagée**.

## Contrats — décisions des 21-22/08/2026

### Le principe qui décide de tout

> **Ce qui était enregistré était-il vrai à l'époque ?**
> Non → on corrige la ligne. Oui → on ajoute une ligne.

`historique_contrats` est un journal en ajout seul. Écraser une valeur
qui était vraie détruit une information irrécupérable — pour le droit
(un renouvellement est un acte daté), pour la paie (`resoudreContrat`
résout le contrat *couvrant la période*), pour l'ancienneté TESA, et
surtout pour **l'annualisation à venir** : un CDI passé de 35 h à 28 h
en cours d'année rend le compteur incalculable si on écrase.

### Où vit l'écriture

**La fiche collaborateur, et elle seule.** L'onglet Contrats est en
lecture seule, sauf le renouvellement en masse.

Décision prise après avoir construit puis supprimé une modale
d'écriture dans l'onglet : deux formulaires pour le même geste
divergent toujours. La fiche présente mieux l'historique d'une
personne ; l'onglet sert au transversal.

⚠️ Corollaire : ne pas réintroduire de geste d'écriture unitaire dans
l'onglet Contrats.

### Deux familles de contrats

- **COURT** : TESA — contrats mensuels, toutes les heures payées
  chaque mois, période civile
- **LONG** : CDI, CDD, APP — annualisés, période décalée

Le comportement du crayon diffère selon la famille **et** la situation
de la ligne :

| Situation | TESA | CDI / CDD / APP |
|---|---|---|
| À venir | tout modifiable | tout modifiable |
| En cours | début, heures, taux, fin | début, taux seulement |
| Terminée | pas de crayon | pas de crayon |

⚠️ **Les heures d'un contrat long commencé sont verrouillées.** Un
changement de temps de travail coupe l'annualisation en deux : il faut
une nouvelle ligne, pas une correction. Message sous le champ grisé
renvoyant vers « + Nouvel événement ».

⚠️ **La date de fin d'un contrat long a son propre bouton**
(« Fin de contrat » / « Modifier la date de fin »), pas le crayon.
Sur un TESA, elle est au crayon.
Le bouton « Modifier la date de fin » passe par `modifier-contrat`,
pas par `cloturer_contrat` — celle-ci ne cible que la ligne ouverte
(`date_fin is null`).

### Le taux horaire

**Il ne crée pas de nouvelle ligne.** Son but est d'approcher un coût,
pas de reconstituer une paie. Une revalorisation est donc une
correction.

⚠️ Conséquence assumée : un coût calculé rétroactivement utilisera le
taux d'aujourd'hui, pas celui de l'époque. **Pour un vrai calcul de
coût, il faudra une table `couts` figée** — même patron que
`paie_detail` pour les jours : on écrit ce qu'on a utilisé, au moment
du calcul.

⚠️ Le taux est exposé par `contrats_liste`, donc toute lecture passe
par une Edge avec vérification du token admin.

### Le matricule Silae

**Il n'a rien à faire dans `historique_contrats`** — il identifie la
personne, pas le contrat. La colonne existe pourtant, et chaque
écriture doit la transporter à l'identique sous peine de l'effacer.

⚠️ `rafraichir_fiche_collab` recopie le matricule du journal vers la
fiche. Un matricule saisi dans la fiche identité sera donc écrasé à la
première écriture de contrat. **Ce n'est pas un bug, c'est le
comportement — mais le champ de la fiche est trompeur.**

À corriger un jour : sortir la colonne du journal. Indolore
aujourd'hui, aucun contrat n'en porte.

### La rupture anticipée

Seul cas où la réalité change sans créer de ligne. On raccourcit
`date_fin` et on pose `rupture_anticipee = true`.

⚠️ **La date initialement prévue est perdue.** Décision assumée : le
drapeau porte l'information.
⚠️ **Les jours au-delà ne sont pas supprimés.** Décision prise contre
la purge, qui aurait pu détruire des saisies réelles ou créer des
orphelins dans `paie_detail` (append-only).

> À rouvrir quand l'annualisation arrivera : l'écart entre prévu et
> réalisé est précisément ce qu'un compteur veut mesurer.

### Les états et les seuils

`contrats_liste(p_historique)` calcule l'état en SQL. Vue par défaut =
contrats **en cours uniquement**.

`fin_proche` = fin dans **10 jours ou moins ET aucune ligne ne suit**
(`a_une_suite` faux). C'est le filtre « **Sans renouvellement** » :
vide en début de mois, plein à l'approche des fins.

⚠️ **Seuil unique à 10 jours**, en base et dans la timeline. 30 jours
rendait tout orange avec des contrats mensuels.
⚠️ Le seuil est en dur. Le rendre réglable suppose une table de
paramètres — chantier « Paramètres » à ouvrir un jour, pas pour un
seul chiffre.

**Timeline de la fiche** : gris = terminé, bleu = à venir, orange =
fin dans 10 jours sans suite, vert = tout le reste. Un contrat borné
n'est pas une anomalie.

### Le compteur d'incohérences

`contrats_incoherences()` compte les contrats échus dont le
collaborateur est encore actif, hors ruptures anticipées.

Affiché seulement s'il est > 0 ; « Voir » bascule en historique
complet, remet les autres filtres à zéro et n'affiche que ces lignes.

⚠️ Un compteur qui ne bouge pas cesse d'être lu. C'est pourquoi les
29 TESA sans date de fin n'y sont **pas** comptés : c'est un retard de
saisie, pas une alerte.

### Le renouvellement en masse

**Le geste le plus répété de l'appli** — trente TESA, douze fois par
an (contrats mensuels).

`renouveler_contrats_lot(ids, date_debut, date_fin, par)`,
transactionnelle : tout ou tien.

⚠️ **TESA uniquement.** Un CDI se poursuit, il ne se renouvelle pas.
La garde porte sur la ligne, pas sur le filtre.
⚠️ **Une seule écriture par ligne** : les contrats sans date de fin ne
sont pas cochables. Poser la date se fait au crayon, un par un.
⚠️ **En cas d'incompatibilité, tout le lot échoue** et le message
NOMME le collaborateur en cause. Sans le nom, l'admin cherche parmi
huit lignes.
⚠️ La RPC ne réutilise pas `ajouter_contrat` : elle refait ses gardes
pour pouvoir nommer le coupable.

### Vocabulaire

- **« Nouvel événement »** plutôt qu'« avenant » : le second est
  juridique et engage.
- **« Sans renouvellement »** plutôt qu'« à renouveler » : le filtre
  décrit une situation, il ne présume pas de la décision.
- **« Récap »** désigne historiquement l'écran des saisies.
- ⚠️ **« Actif / inactif »** est ambigu : dans l'appli il qualifie un
  compte qui fonctionne, pas quelqu'un en poste. Filtre retiré de
  l'onglet Contrats pour cette raison.

### La règle d'activité (pas encore automatisée)

**Un collaborateur est actif s'il existe un contrat couvrant
aujourd'hui ou demain.** Une condition, deux effets : activation la
veille du premier jour, désactivation le lendemain du dernier.

⚠️ « Demain » et non « aujourd'hui » : le cron de génération des jours
tourne vers 00 h 10 ; activer la veille supprime la course entre les
deux tâches.
⚠️ **Les administrateurs sont exclus** de la désactivation. Confirmé
par les données : deux des trois admins n'ont aucun contrat en vigueur.
⚠️ À brancher **en dernier**, quand les contrats sont justes.

### Ce que l'appli ne fait pas

**Elle ne calcule aucune rémunération.** Le taux est une information à
recopier vers la MSA, comme les heures.

⚠️ Ce principe va être mis à l'épreuve par l'annualisation (1593 h sur
12 mois du 1/3 au 28/2, mensuel théorique de 132,75 h pour un 35 h).
`heures_hebdo` deviendra alors le **diviseur d'un calcul**, plus une
donnée cosmétique — et un contrat sans heures renseignées rendra le
compteur incalculable.

⚠️ **`echu_actif` ne se déclenche que si AUCUN AUTRE contrat ne
couvre aujourd'hui.** Sans cette condition, un collaborateur ayant
deux lignes (un TESA terminé, un CDD en cours) apparaissait en
« échu, encore actif » — l'état est calculé ligne par ligne, pas
personne par personne. Corrigé le 26/08 dans `contrats_liste` et
`contrats_incoherences`.

## Sécurité des accès — état au 25/08/2026

> **Remplace les sections « Sécurité des accès » du 23/08.** Trois
> tables ont été fermées depuis.

### ⚠️ Le piège à connaître avant d'écrire du code

**Trois tables ne sont plus lisibles par `anon`.** Un `.from(...)` sur
l'une d'elles dans le front renvoie un **401 Unauthorized** — erreur
qui ne dit pas pourquoi.

| Table | Fermée le | Pourquoi |
|---|---|---|
| `historique_contrats` | 23/08 | porte les taux horaires |
| `collaborateurs` | 25/08 | **porte tous les tokens collab** |
| `equipes` | 25/08 | **porte tous les tokens manager** |

Plus `admins` et `journal_editions`, qui n'ont jamais été ouvertes.

**Toute lecture de ces tables passe par une Edge.**

### Les Edge de lecture, et ce qu'elles servent

| Edge | Pour qui | Ce qu'elle renvoie |
|---|---|---|
| `contrats-liste` | admin | routée par `action` : `liste`, `collab`, `paie` |
| `collaborateurs-liste` | admin | tous les collaborateurs, tokens compris |
| `equipes-liste` | admin | les équipes + `manager_token` (bouton « Copier lien ») |
| `manager-equipe` | manager | équipe + membres + jours, **un seul appel** |
| `collab-session` | collaborateur | identité, **une seule résolution du token** |

⚠️ **`collab-session` ne renvoie que neuf champs** : `collab_id`,
`prenom`, `nom`, `nom_affiche`, `structure`, `type_periode`,
`equipe_id`, `role`, et `manager_token` **uniquement si le
collaborateur est responsable**. Pas son propre token, pas l'email,
pas le téléphone, pas le matricule.

⚠️ **L'Edge `collab-session` relaie `data.collab` tel quel.** Ajouter
un champ à la RPC suffit — aucun déploiement d'Edge nécessaire. C'est
comme ça que `manager_token` a été ajouté le 25/08.

⚠️ **`manager_equipe` ne renvoie pas les tokens des membres.**

### Ce qui reste ouvert en lecture

| Table | Lue par | Ce qui fuit |
|---|---|---|
| `jours` | `index.html` | les heures |
| `periodes` | `index.html` | peu sensible |
| `paie_detail` | `admin-v2.html` (5 lectures) | les heures |
| `recap_paie` | `admin-v2.html` (3 lectures) | les heures |

⚠️ **C'est une fuite de données, mais sans moyen d'action** : plus
aucun token n'est accessible, donc plus personne ne peut prendre une
identité ni écrire. Le plus grave est traité.

⚠️ **`paie_detail` et `recap_paie` ne sont PAS un gain facile**, malgré
ce que j'avais annoncé : huit lectures subsistent dans l'admin, dont
deux via `fetchAllPages` — donc **la pagination est à reproduire**.
Compter une demi-journée.

### La méthode, validée cinq fois

Ordre **non commutatif** :

1. créer la RPC de remplacement (aucun risque, rien ne l'appelle)
2. créer l'Edge, **en gardant la compatibilité ascendante** si elle
   existe déjà
3. déployer l'Edge, **vérifier que l'ancien front marche encore**
4. adapter le front, tester en local
5. pousser, **vérifier en prod**
6. **révoquer le `SELECT` en dernier**

⚠️ Marche arrière immédiate : `grant select on <table> to anon;`

⚠️ **Pour `index.html` (soixante personnes), ajouter une étape** :
attendre deux ou trois jours d'usage réel avant de révoquer. Fait pour
`collaborateurs` — révoqué le mardi 25/08 après vérification que
**49 collaborateurs avaient saisi** depuis le déploiement du dimanche
soir. C'est cette vérification qui prouve que le nouveau code est
éprouvé, pas l'absence de plainte.

```sql
select count(distinct collab_id), max(date_derniere_modif)
from jours where date_jour >= '<date du déploiement>';
```

### Ce qu'on a appris sur les fronts

**`index.html`**
- **Le Service Worker ne cache PAS `index.html`**, seulement les
  polices Google. Aucun risque de servir une version périmée du code.
- ⚠️ **Un onglet resté ouvert exécute l'ancien code** jusqu'au prochain
  rechargement. Un rafraîchissement règle tout — mais autant éviter de
  révoquer un jour de forte activité.
- ⚠️ **La bibliothèque Supabase vient d'un CDN externe**
  (`cdn.jsdelivr.net`). Sans réseau, `createClient` n'existe pas et le
  script s'arrête **avant tout message d'erreur** — d'où un chargement
  qui tourne en rond. **Point de défaillance unique : si le CDN tombe,
  personne ne saisit.** À porter au backlog.
- **Pas de mode hors ligne**, pas de file d'attente. Tout échoue
  immédiatement sans réseau.
- **Rien ne se rafraîchit automatiquement.** Un onglet ouvert toute la
  journée garde les données du matin et ne bascule pas au jour suivant
  après minuit. Le filet est côté serveur : `sauver-saisie` revérifie
  tout contre la base vivante.
- ⚠️ **« Aucun jour trouvé » s'affiche aussi quand le réseau est
  coupé** — message trompeur, le collaborateur croit qu'il n'a rien
  saisi. Backlog.

**`manager.html`**
- Le token manager **n'est pas stocké** (ni cookie, ni localStorage).
  Il ne vit que dans l'URL.
- ⚠️ Mais il **n'est jamais envoyé** : le manager passe par le bouton
  « Mon équipe » de son espace collaborateur, qui construit le lien à
  la volée depuis `collab-session`. Le token ne circule pas hors de
  l'appli.
- Le bouton « Copier lien » de l'onglet Équipes est donc peut-être un
  vestige.

### Mesures de latence (23/08, en prod)

| | |
|---|---|
| Lecture directe | ~116 ms |
| Edge à froid | ~660 ms |
| Edge réchauffée | ~360 ms |

⚠️ Soit **250 à 500 ms de plus** par appel. Négligeable devant la
latence réseau d'un téléphone en 4G — mais c'est pourquoi on a réduit
le nombre d'appels : `index.html` fait **une** résolution du token au
lieu de trois, `manager.html` fait **un** appel au lieu de trois
lectures.

### Observabilité

- **Logs Supabase : 7 jours de rétention** sur le plan Pro. Les Log
  Drains coûtent 60 $/mois — hors de proportion.
- ⚠️ **Les tokens apparaissent en clair dans les logs** (ils sont dans
  l'URL des requêtes). Quiconque accède au tableau de bord les lit.
- **Volume de référence : ~5 600 requêtes sur 7 jours** pour soixante
  personnes. Une aspiration de base laisserait une signature évidente.
- **Observability → Overview** (icône longue-vue) donne CPU, disque,
  connexions. Au 23/08 : 3 % CPU, 14 % disque, 7 connexions sur 60.

⚠️ **Aucune alerte automatique.** Il faut aller regarder.

### Ce qui reste non traité

⚠️ **Le token dans l'URL** (`?id=xxx`). Il est aussi en cookie et
localStorage, donc `history.replaceState()` serait possible. **Non
fait** : l'appli est installable en PWA, et si l'icône d'accueil pointe
vers une URL nettoyée, l'ouverture suivante dépend entièrement du
cookie — que le système peut purger. Risque de déconnecter des
collaborateurs. À vérifier avant de tenter.

⚠️ **CORS ouvert à `*`.** Le restreindre élimine les appels depuis un
navigateur tiers, mais **ne protège pas** d'un appel en ligne de
commande, ni des lectures directes qui restent. Utile, pas décisif.

⚠️ **Tokens de huit caractères, sans expiration ni rotation.** Un token
volé l'est pour toujours. Chantier Auth au sens large.

⚠️ **Postgres 17.6.1.127**, la dernière est 17.6.1.155. Correctif
mineur, redémarrage de la base. **À faire un dimanche soir.**

⚠️ **`TRUNCATE` encore accordé à `anon`** sur toutes les tables.
Probablement inexploitable via PostgREST, mais sans raison d'être :
`revoke truncate on all tables in schema public from anon;`

### Deux points de vocabulaire, pour éviter une fausse alerte

**Une policy RLS autorise, un `GRANT` permet.** Des policies traînent
avec `qual = true` sur plusieurs tables — **elles n'ont aucun effet**
tant que le `GRANT` manque. Ne pas s'en alarmer : c'est ce qui m'a fait
conclure à tort, le 23/08 au matin, que l'écriture était ouverte.

⚠️ **La clé publique dans le code source n'est pas une faille** : elle
est publique par conception. **La protection vient des `GRANT`, pas du
secret de la clé.** Tout ce qui vit dans le navigateur est visible et
contournable — la sécurité doit vivre en base.


---

## Le journal des déclarations

### Le besoin

Mettre les contrats à jour dans l'appli ne suffit pas : il faut les
reporter dans la **MSA** (TESA) ou dans **Silae** (le reste). C'est
cette étape qui n'avait aucun support, et où les oublis se produisent.

**Le process, dans cet ordre :** appli → journal → MSA/Silae.
⚠️ **Aucun geste dans MSA ou Silae qui ne passe pas d'abord par
l'appli.** Sans cette rigueur, le journal dérive.

### Pourquoi pas une liste de tâches

Une table de tâches remplie automatiquement à chaque écriture aurait
été plus lourde et risquait de se désynchroniser. **L'admin déclare
par lots, une fois par mois** — une vue calculée à la demande suffit.

### Le fonctionnement

- `journal_editions (id, edite_le, edite_par, borne_debut, contenu)` —
  une ligne par édition.
- `journal_mouvements()` — tout ce qui a été **créé ou modifié**
  depuis la dernière clôture (`created_at` ou `modifie_le` postérieur
  à la borne).
- `journal_cloturer(par, contenu)` — fige et archive.
- `journal_archives()` — les éditions passées.

**Ventilation : structure → destination (MSA/Silae) → collaborateur.**
⚠️ C'est **la structure du mouvement** qui décide, pas celle de la
personne. Un changement de structure fait donc apparaître le
collaborateur dans deux blocs — c'est voulu : quand on est dans la MSA
pour la SAS, on ne veut pas voir ce qui concerne la SCEA.

⚠️ Le **matricule** ne s'affiche que pour Silae. Un TESA n'en a pas
besoin.

### Ce que le journal ne sait pas faire

⚠️ **Il ne peut pas distinguer une fin de contrat d'une autre
modification.** `historique_contrats` ne garde que `modifie_le`, pas le
détail de ce qui a changé. Toute modification s'affiche donc
« Contrat modifié — vérifier », avec les valeurs actuelles.

Un journal des changements (trigger + table) aurait donné le détail,
mais : maintenance à chaque colonne ajoutée, et pollution par les
corrections de frappe faites trente secondes après la saisie.
**Écarté volontairement.**

### L'archive est une photo, pas un recalcul

Le **texte affiché** est stocké dans `contenu` au moment de la
clôture. Rouvrir une édition passée montre exactement ce que l'admin
avait sous les yeux ce jour-là.

⚠️ Un recalcul aurait dérivé : un contrat corrigé après coup voit son
`modifie_le` avancer et **sortirait** de la fenêtre d'une archive
passée.

⚠️ Conséquence : le journal en cours est en **HTML stylé**, l'archive
en **texte brut**. Les deux ne se ressemblent pas — assumé.

### La clôture est explicite

Un bouton, jamais automatique. Ouvrir le journal pour regarder ne doit
pas remettre le compteur à zéro.

⚠️ Deux admins qui éditent à deux jours d'intervalle : le second ne
verra que ce qui a bougé entre les deux. C'est le comportement voulu.

### L'impression

⚠️ **Fenêtre `about:blank` dédiée**, sur le patron du PDF des relevés.
Raison : le pied de page automatique du navigateur affiche l'URL —
**donc le token admin**. Une feuille imprimée oubliée sur un bureau
donnait l'accès complet à l'administration.

`@page { margin }` ne supprime pas ce pied de façon fiable dans
Chrome ; seule la fenêtre dédiée le règle vraiment.

