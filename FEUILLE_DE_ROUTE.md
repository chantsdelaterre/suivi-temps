# FEUILLE DE ROUTE — suivi-temps

> Document de suivi unique. **Remplace `BACKLOG.md`.**
> `[ ]` à faire · `[x]` fait · ~~barré~~ abandonné.
> Établi le 12/08/2026 — sources : BACKLOG, reconnaissance du 12/08,
> session du 09/08, inventaire CC du 12/08, documents d'amorçage.
>
> Tout le passif technique est concentré dans **`admin-v2.html`**.
> `index.html` et `manager.html` sont sains (0 vestige GAS, 100 % Supabase).

---

## 1 · CORRIGER

### 1.1 Bugs actifs

- [ ] **`chargerRecap` lit TOUTE la table `jours`, sans aucun filtre.**
  ~18 000 lignes à un an, tronquées à 1000 par PostgREST. L'onglet Récap
  affiche donc déjà des « dernières saisies » fausses pour les collaborateurs
  les moins récents — silencieusement. *Seul bug de données actif.*
  → filtrer par période courante, ou `fetchAllPages`. **2 h**

- [ ] **Les deux boutons de l'onglet Périodes ne font rien.**
  `sauverPeriode` appelle du GAS disparu → `ReferenceError`, et son `catch`
  **simule un succès** (ferme la modale, recharge la liste). L'admin croit
  avoir enregistré. `supprimerPeriode` affiche « Erreur réseau » — faux
  motif, mais échec visible.
  **Décision requise** : retirer, ou écrire une Edge `modifier-periode`.
  Aucune Edge ne crée / modifie / supprime une période aujourd'hui.
  *Le code actuel est faux de toute façon : il force `statut:'planifiee'`
  même en modification, et envoie `dateCloture`, colonne abandonnée.
  Et supprimer une période laisserait des orphelins — `periode_id` n'a
  aucune clé étrangère.* **2 h retirer · 1 j réimplémenter**

- [ ] **`fetchJoursCollab` non paginée** — tous les jours d'un collab, sans
  borne de date. Croît indéfiniment. Bouton « Voir » du Récap. **1 h**

### 1.2 Sécurité

- [ ] **Tokens collaborateur en `Math.random()`** ⚠️ *à confirmer* —
  8 caractères, suite prédictible. → `crypto.randomUUID()` dans
  `creer-collab`, régénérer, rediffuser les liens. **2 h**

- [ ] **Token admin en clair dans l'URL, sans expiration.** Rotation
  immédiate possible. **1 h**

- [ ] **`admin.html` (ancien backoffice GAS) toujours servi par GitHub
  Pages** → double backoffice accessible. **30 min**

### 1.3 Nettoyage

- [ ] **12 fonctions mortes dans `admin-v2.html`** : `initPaie`,
  `toggleValidation`, `sauverNote`, `sauverJourPaie`, `sauverRemarque`,
  `sauverJour` (GAS) · `grouperParSemaine`, `calculerPaiePeriode`,
  `rechargerDetailPaie`, `genNomPeriode`, `genTokenCollab`,
  `rendreModalDeplacable`. Plus la globale morte `recapPeriodeId`.
  Et `Code.gs` (ancien back-end complet).
  ⚠️ Ne pas toucher aux 2 fonctions GAS **vivantes** (§1.1) avant décision.
  **2 h**

- [ ] **2 ids dupliqués**, tous deux zone Détail de paie ↔ modale Récap :
  `modal-note-admin` et `btn-valider-collab`. Ça marche par l'ordre du
  HTML — un déplacement de bloc inverserait le comportement. **1 h**

- [ ] **Vestige `ferie:'Férié'`** (et `conge`, `absence`) dans le mapping de
  libellés de `renderSaisiesPaie`, pour des types absents de la base.
  Piège direct pour le chantier fériés. **15 min**

- [ ] **`garantirEntreeRecapCloture`** compare sur `_paieCurrentCollab` brut
  quand `upsertRecapPaieCourant` décode d'abord. **15 min**

- [ ] **`calculTotal`** (index.html) et **`fmtDate`** (manager.html), mortes.
  **10 min**

### 1.4 Performance

- [ ] **`calculerCountsPaie`** rapatrie tout `paie_detail` de toutes les
  périodes pour un `count(distinct collab_id)` — ~20 000 lignes/an.
  → RPC d'agrégation. **3 h**

- [ ] **`historique_contrats` non paginée** dans
  `calculerPaieDepuisPaieDetail`. **1 h**

- [ ] **`ajuster-paie` non transactionnelle** — `UPDATE` ligne par ligne,
  pas de rollback. Se répare au second essai (lot renvoyé à l'identique),
  d'où le classement ici. → RPC PL/pgSQL. **½ j**

### 1.5 UX

- [ ] Emoji ⏹️ non rendu sur macOS Chrome (carré vide)
- [ ] Titre « Paie — périodes clôturées » inexact depuis le 09/08
- [ ] « Aucune période clôturée. » → « Aucun relevé clôturé. »
- [ ] Rustine redondante dans `toggleHeuresEdit`
- [ ] `ouvrirDetailArchive` exécute `renderPaie` inutilement sur période ouverte
- [ ] 17 « No label associated with a form field » (accessibilité)
- [ ] Largeur du tableau Détail avec les 2 colonnes ajoutées ⚠️ *à vérifier*

---

## 2 · CHANTIERS OUVERTS

- [ ] **Jours fériés & journées de solidarité** — conçu, amorçage v2 prêt.
  **Bloqué** : capture du formulaire MSA + 3 réponses de Pauline
  (majoration sur fériés travaillés, articulation des 15 %, seuil
  d'ancienneté).
  *Décision actée : la règle ne doit JAMAIS être codée en dur — une note de
  synthèse a donné trois réponses différentes à la même question.*

- [ ] **Désactivation d'un collab en fin de contrat** — spec écrite, non
  codée. **Geste manuel décidé** (un cron désactiverait deux des trois
  admins, sans contrat en vigueur). Manque : un signal dans l'UI, parce que
  le geste s'oublie — cas Jonas, 40 jours morts générés après sa fin de
  contrat.

- [ ] **Les 113 ajustements sans `date_ajuste_admin`** — non
  reconstituables. **Recommandation : ne rien inventer.** Une date
  conventionnelle serait indistinguable d'une vraie dans six mois. La
  colonne dit « Modif admin » sans date, la doc explique pourquoi.

- [ ] **Marqueur « modifié après validation »** dans la liste Clôturées.
  Remplace l'ancienne puce « contrôle de statut », qui appelait une
  correction **contredisant la décision du 14/06** (verrou lecture seule
  abandonné). Demande une RPC d'agrégation.

- [ ] **« Jonas puissance deux »** — changement de contrat en cours de
  période. Le lot 2 ne traite que les départs. *Question annexe : COLL017
  a-t-il saisi des heures le 17/07, jour non couvert par un contrat ?*

- [ ] **Authentification admin** — token applicatif + `verify_jwt = false`
  sur 13 Edge. Migrer vers Supabase Auth (inclus dans l'abonnement) apporte
  mot de passe, session expirante, révocation. **1–2 j**

- [ ] **Révocation d'un token collaborateur** sans désactiver la personne.
  N'existe pas.

- [ ] **Versionner le schéma** (`supabase db pull`). `jours`, `periodes`,
  `collaborateurs`, `equipes` n'ont aucun `CREATE TABLE` versionné.
  ⚠️ **Changement de méthode, pas une tâche** : les migrations remplacent
  l'intervention directe dans le SQL Editor. Bénéfice annexe : une base
  locale de test — aujourd'hui chaque essai se fait en prod. **½ j**

---

## 3 · ÉVOLUTIONS

**Métier**

- [ ] Onboarding TESA self-service (token privé → formulaire → Yousign Plus)
- [ ] **Signature des RIH** — trois voies : Yousign API (~104 €/mois,
  500 sign./an, insuffisant · l'envoi en masse ne s'applique pas, il envoie
  le *même* document) · Desk RH/eDocSign (450 € + 0,25 €/doc ≈ 7 €/mois) ·
  accusé horodaté dans l'appli (quasi gratuit, `statut_signature` existe
  déjà — **question à l'expert-comptable : suffit-il juridiquement ?**)
- [ ] Onglets **Paramètres** et **Aide**, distincts
- [ ] Compteurs annuels (CP, journée de solidarité)
- [ ] Module Cantine ⚠️ *collision : sa table `fermetures` inclut les fériés*
- [ ] Export MSA / Silae
- [ ] Taux horaire dans l'appli ? *bloque le cas des 3 %*

**Technique**

- [ ] Automatiser le déploiement — **l'ordre Edge→front n'est garanti par
  rien aujourd'hui**. Action GitHub, ~20 lignes. **3 h**
- [ ] Tests sur 3 règles de paie : `calculerPaieDepuisPaieDetail`, fenêtre
  J-5, limite de 3 modifications. Pas la couverture — le filet. **½ j**
- [ ] `_shared` pour `json()` / `corsHeaders`, recopiés dans les 13 Edge
- [ ] Documenter la conservation des données (une page)

**Horizon lointain**

- [ ] Commercialisation « Mes Heures Pro ». ⚠️ Repose **l'architecture
  entière** : multi-tenant, auth réelle, RLS par organisation. Changement de
  nature, pas de degré. **Ne rien concevoir aujourd'hui pour ce cas.**

---

## 4 · NE PAS CHANGER

- **Écritures par Edge en `service_role`, `anon` en lecture seule**,
  revalidation côté serveur. Modèle à reconduire tel quel.
- **`historique_contrats` en journal ajout-seul** et **double couche de
  `paie_detail`**.
- **La re-validation depuis Détail EST le mécanisme de correction** d'un
  relevé clôturé (14/06). Ne pas griser ce bouton — la régression du 09/08
  venait de là.
- **Pas de cache sur la liste des candidats** à la clôture anticipée : le
  bloc doit se reconstruire sans le candidat traité.
- **La borne se préserve par omission** — `valider-recap` filtre par
  `if (k in recap)` : clé absente = valeur préservée, `null` = effacée.
- **Pagination sur colonne unique** (`id`), jamais `date_jour`. L'ordre
  métier se refait en mémoire.
- **`window.open` avant les `await`**, sinon Chrome bloque.
- **Edge avant front**, jamais l'inverse.

---

## 5 · MÉTHODE

- **Un diff MONTRÉ n'est pas un diff APPLIQUÉ.** Incident du 09/08 :
  plusieurs recettes sur du code inexistant, puis 124 lignes importées en
  prod. Tout prompt finit par « montre-moi la ligne telle qu'elle est
  DÉSORMAIS et confirme que le fichier EST modifié ».
- **Avant tout test** : `<fonction>.toString().includes('<marqueur>')`.
- **Recette console sur localhost, jamais sur la prod.**
- **Faire PROPOSER CC avant d'écrire** dès qu'un diff touche une fonction
  partagée. Trois pièges évités ainsi le 09/08.
- **Le format « Update(fichier) » de CC n'est pas fiable** — il mélange
  lignes supprimées et conservées. Seul le verbatim l'est.
- **Jamais `git add .`** — fichiers nommés. Le `.gitignore` ne couvre pas
  les `.csv`.
- **Push au Terminal natif**, token temporaire révoqué après. Jamais CC.
