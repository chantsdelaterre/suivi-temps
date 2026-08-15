# FEUILLE DE ROUTE — suivi-temps

> Document de suivi unique. **Remplace `BACKLOG.md`.**
> `[ ]` à faire · `[~]` partiellement fait · `[x]` fait · ~~barré~~ abandonné.
> Établi le 12/08/2026 — sources : BACKLOG, reconnaissance du 12/08,
> session du 09/08, inventaire CC du 12/08, documents d'amorçage.
>
> Tout le passif technique est concentré dans **`admin-v2.html`**.
> `index.html` et `manager.html` sont sains (0 vestige GAS, 100 % Supabase).

---

## 1 · CORRIGER

### 1.1 Bugs actifs

- [x] **`chargerRecap` lit TOUTE la table `jours`, sans aucun filtre.**
  ~18 000 lignes à un an, tronquées à 1000 par PostgREST. L'onglet Récap
  affichait des « dernières saisies » fausses pour les collaborateurs les
  moins récents — silencieusement. **Fait (8c34be5)** : remplacé par la RPC
  d'agrégation `derniere_saisie_par_collab()` (le critère « saisi » vit
  désormais en base).

- [x] **Les deux boutons de l'onglet Périodes ne font rien.**
  `sauverPeriode` appelait du GAS disparu → `ReferenceError`, et son `catch`
  **simulait un succès** (fermait la modale, rechargeait la liste). L'admin
  croyait avoir enregistré. `supprimerPeriode` affichait « Erreur réseau » —
  faux motif, mais échec visible.
  **Décision : RETIRÉS. Fait (c861b2c)** — les boutons Nouvelle période /
  Modifier / Supprimer, la modale `#modal-periode` et les 4 fonctions
  associées sont supprimés ; l'onglet Périodes est en consultation. Le cycle
  de vie reste piloté par le cron ; une correction ponctuelle se fait en SQL,
  avec `sql/controle_jointure_periodes.sql` pour vérifier la jointure après
  coup. (Pas d'Edge `modifier-periode` : un bouton naïf casserait l'invariant
  de jointure — trois gestes coordonnés requis.)

### 1.2 Sécurité

- [x] **Tokens collaborateur en `Math.random()`** — confirmé : c'était bien
  `Math.random()`, 8 caractères, suite prédictible. **Fait (8b5b0e5)** :
  `crypto.getRandomValues`, 14 caractères, Edge `creer-collab` déployée le
  15/08. **Décision actée : PAS de régénération des 59 tokens existants** —
  recontacter 59 personnes est disproportionné au regard de ce qu'ouvre un
  token collaborateur (ses propres heures, en saisie bornée à 3 modifications
  sur 5 jours). Les anciens s'éteindront au fil des fins de contrat.

- [~] **Token admin en clair dans l'URL, sans expiration.** **Rotation faite
  le 15/08** pour les trois administrateurs (Guillaume, Elsa, Pauline) via
  `update admins set token = encode(gen_random_bytes(10),'hex')` — invalide ce
  qui traînait dans les captures et historiques.
  ⚠️ N'apporte **NI expiration NI traçabilité** — le vrai correctif reste le
  chantier Auth (§2). À noter : la table `admins` porte une colonne `actif` →
  la révocation d'un accès existe déjà, sans passer par Auth.

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
  - Les tokens admin vivent dans une table `admins` (nom, token, actif), lue
    par la RPC `verifier_admin`. Ils ne sont **PAS** dans `collaborateurs`.
  - `verifier_admin` renvoie un **NOM, jamais persisté** : aucune écriture ne
    dit QUI l'a faite. Auth apporterait cette identité.

- [ ] **Révocation d'un token collaborateur** sans désactiver la personne.
  N'existe pas.

- [ ] **Versionner le schéma** (`supabase db pull`). `jours`, `periodes`,
  `collaborateurs`, `equipes` n'ont aucun `CREATE TABLE` versionné.
  ⚠️ **Changement de méthode, pas une tâche** : les migrations remplacent
  l'intervention directe dans le SQL Editor. Bénéfice annexe : une base
  locale de test — aujourd'hui chaque essai se fait en prod. **½ j**

- [ ] **Rapport quotidien du cron par mail.** `trigger_quotidien()` construit
  déjà un rapport texte (4 étapes, avec le message d'erreur de chacune) —
  l'en-tête du fichier dit qu'il est « destiné à être envoyé par mail plus
  tard via une Edge Function ».
  **Aujourd'hui ce rapport n'est lisible NULLE PART** : chaque étape attrape
  ses exceptions, donc `pg_cron` voit toujours `succeeded`, et
  `return_message` ne journalise que « 1 row », pas le contenu. Trente nuits
  consécutives « réussies » ne prouvent rien.
  Contenu à prévoir, au-delà du rapport technique :
  · **fins de contrat à J-5** (« Havva KUCUK, fin de contrat le 18/08 »)
  · **contrats échus, collaborateur encore actif** — le cas Jonas, qui aurait
    crié six semaines au lieu de générer 40 jours morts
  · **clôtures anticipées en attente** — la RPC `candidats_cloture_anticipee()`
    renvoie déjà exactement ça
  ⚠️ Prévoir aussi une **table `journal_cron`** (une ligne par nuit) : sans
  elle, le mail est la seule trace, et un envoi en panne nous ramène à
  l'aveuglement actuel.
  *Edge d'envoi via Resend + RPC d'état + job pg_cron. 1 j*

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
- **Un inventaire n'a pas plus d'autorité qu'un diff montré.** L'item
  « fetchJoursCollab non paginée » a figuré en §1.1 sur la foi d'un tableau
  d'inventaire, alors que la fonction porte un `.limit(60)` depuis toujours —
  la lecture initiale s'était arrêtée aux premières lignes. Toute entrée
  d'inventaire qui commande un correctif se revérifie sur le corps complet
  avant d'être inscrite.
- **Avant tout test** : `<fonction>.toString().includes('<marqueur>')`.
- **Recette console sur localhost, jamais sur la prod.**
- **Faire PROPOSER CC avant d'écrire** dès qu'un diff touche une fonction
  partagée. Trois pièges évités ainsi le 09/08.
- **Le format « Update(fichier) » de CC n'est pas fiable** — il mélange
  lignes supprimées et conservées. Seul le verbatim l'est.
- **Jamais `git add .`** — fichiers nommés. Le `.gitignore` ne couvre pas
  les `.csv`.
- **Push au Terminal natif**, token temporaire révoqué après. Jamais CC.
- **Un contrôle de « fonction morte » doit chercher le nom NU, pas seulement
  `fn(`.** `rendreModalDeplacable` a figuré dans deux inventaires successifs
  comme morte : elle est passée en référence dans un
  `forEach(rendreModalDeplacable)`, sans parenthèses. La supprimer aurait levé
  une `ReferenceError` au chargement et tué toute la page. Chercher aussi
  `map(fn)`, `.then(fn)`, `addEventListener('x', fn)`, `setTimeout(fn, …)`.
