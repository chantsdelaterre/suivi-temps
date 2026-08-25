# BACKLOG — Suivi des temps Chants de la Terre

> Régénéré le 25/08/2026. Remplace la version du 11/07, dont la moitié
> était faite. Source unique des chantiers restants.
> (Décisions et raisons dans `CLAUDE.md`.)

---

## 🔴 PRIORITÉ 1 — Ce qui protège la paie

### 1a. Cron d'activation / désactivation
**Décidé, pas fait.** Aujourd'hui l'admin active et désactive à la main.

**La règle, en une phrase :** un collaborateur est actif s'il existe un
contrat couvrant **aujourd'hui ou demain**.

Une condition, deux effets : activation la veille du premier jour,
désactivation le lendemain du dernier.

⚠️ « Demain » et non « aujourd'hui » : le cron de génération des jours
tourne vers 00 h 10 ; activer la veille supprime la course entre les
deux tâches.
⚠️ **Les administrateurs sont exclus** de la désactivation. Confirmé
par les données : deux des trois admins n'ont aucun contrat en vigueur.
⚠️ **Condition préalable : les contrats doivent être justes.** Le
filtre « Sans renouvellement » de l'onglet Contrats est le point de
contrôle.

### 1b. Contrôle de cohérence des totaux
**Le risque le plus grave identifié : la corruption silencieuse.**
Tout semble normal, les chiffres sont plausibles, mais les relevés sont
faux — et personne ne s'en aperçoit avant la paie.

Une RPC qui compare `jours.total_heures` au total recalculé depuis les
créneaux, pour tout le monde. Diagnostic ponctuel d'abord ; si la base
est saine, en faire un contrôle mensuel.

⚠️ Raison : **trois calculs à trois moments** — le navigateur du
collaborateur au chargement, l'Edge `sauver-saisie` à l'écriture, le
recalcul admin depuis `paie_detail`. S'ils divergent d'une ligne
quelque part, l'écart est invisible.

### 1c. Surveillance externe
**Rien ne préviendrait si l'appli tombait entièrement.** Une
surveillance interne ne détecte pas sa propre panne : si la base tombe,
le cron de surveillance tombe avec elle.

Un service tiers gratuit qui appelle l'appli toutes les heures et
alerte si elle ne répond pas. Dix minutes de configuration.

⚠️ **Principe à tenir : le silence est le signal normal.** Un mail
quotidien « tout va bien » devient invisible en une semaine, et le jour
où il dit autre chose, personne ne le lit. Trois alertes par an qu'on
lit valent mieux que trois cent soixante-cinq qu'on ignore.

---

## 🟠 PRIORITÉ 2 — L'annualisation

**Le gros morceau, pas encore conçu.**

Un CDI à 35 h doit travailler **1593 h sur douze mois**, du **1er mars
au 28 février**, soit **132,75 h en moyenne par mois**. Un salarié qui
fait 150 h a un solde de +17,25 h en fin de mois, cumulé sur la
période. Il faut produire chaque mois un état : « J. Kern +68 h au
30/08 ».

⚠️ **Ce chantier met à l'épreuve le principe « l'appli ne calcule
aucune rémunération ».** `heures_hebdo` cesse d'être une donnée à
recopier pour devenir **le diviseur d'un calcul** — et un contrat sans
heures renseignées rend le compteur incalculable.

⚠️ **Un changement de temps de travail coupe la période en deux.**
Passage à mi-temps au 1er septembre : le théorique vaut 132,75 h
jusqu'en août, 66,375 h ensuite. Le cumul doit additionner deux
segments avec deux références. **C'est ce qui rend la règle « avenant,
pas correction » indispensable** — une modification écrasée rend le
compteur faux pour toute l'année.

⚠️ **Trois découpages temporels coexistent** : les périodes civiles,
les périodes décalées, et l'année d'annualisation (1/3 → 28/2). Le
compteur devra savoir lequel il utilise.

⚠️ **Les TESA ne sont pas concernés** : toutes leurs heures sont payées
chaque mois.

### À rouvrir quand ce chantier arrivera
La **rupture anticipée** perd la date initialement prévue (décision du
21/08, drapeau `rupture_anticipee`). Or l'écart entre prévu et réalisé
est exactement ce qu'un compteur d'annualisation veut mesurer.

---

## 🟡 PRIORITÉ 3 — Saisie collaborateur

### Saisie au fil de la journée
**Conçu, à coder.** Brouillon en localStorage — ne touche ni la base,
ni le quota de trois modifications, ni la validation. À l'ouverture, si
un brouillon du jour existe, rouvrir directement sur le formulaire
pré-rempli avec un bandeau « Brouillon en cours ». Effacé à la
validation et à « Vider les créneaux ».
(Maquette faite ; bandeau orange ou vert à trancher au codage.)

### Voir toute la période, modifier les cinq derniers jours
Le collaborateur ne voit aujourd'hui que quelques jours. Lui donner la
vue d'ensemble de la période en cours, **en consultation**, avec
seulement les cinq derniers jours modifiables.

⚠️ **À concevoir sérieusement** : il faudra distinguer visuellement le
modifiable du consultable, sinon on crée de la frustration
(« pourquoi je ne peux pas cliquer ici ? »).

### Drummer cyclique et boutons de saisie
Le sélecteur d'heures **butte** en haut et en bas — le rendre bouclant
(00 ↔ 45). Front pur.
Achever les boutons de saisie (chantier commencé).

### Message trompeur hors ligne
⚠️ « **Aucun jour trouvé** » s'affiche aussi quand le réseau est coupé.
Le collaborateur croit qu'il n'a rien saisi alors que c'est sa
connexion.

---

## 🔵 SÉCURITÉ — ce qui reste

*(État complet dans `CLAUDE.md`. Trois tables fermées les 23 et 25/08 :
`historique_contrats`, `collaborateurs`, `equipes`.)*

### Fermer `paie_detail` et `recap_paie`
⚠️ **Ce n'est PAS un gain facile**, contrairement à ce qui a été
annoncé un moment : **huit lectures** subsistent dans `admin-v2.html`,
dont deux via `fetchAllPages` — **la pagination est à reproduire**.
Compter une demi-journée.

Ce qui fuit : les heures de tout le monde. **Fuite de données, mais
sans moyen d'action** — plus aucun token n'est accessible.

### Sortir la bibliothèque Supabase du CDN
La figer dans le dépôt plutôt que de la charger depuis
`cdn.jsdelivr.net`.

⚠️ **Point de défaillance unique** : sans ce CDN, `createClient`
n'existe pas, le script s'arrête **avant tout message d'erreur**, et
l'écran tourne en rond. Découvert par accident le 23/08.

⚠️ **Contrepartie** : plus de correctifs automatiques. Soit vérifier la
version deux fois par an, soit l'accepter — une bibliothèque cliente
qui parle à une API stable ne pourrit pas vite.

### Divers
- **CORS ouvert à `*`** sur toutes les Edge. Le restreindre élimine les
  appels depuis un navigateur tiers, mais **ne protège pas** d'un appel
  en ligne de commande. Utile, pas décisif.
- **`TRUNCATE` encore accordé à `anon`** sur toutes les tables :
  `revoke truncate on all tables in schema public from anon;`
- **Postgres 17.6.1.127 → 17.6.1.155.** Correctif mineur, redémarrage
  de la base. **Un dimanche soir.**
- **Chantier Auth** : tokens de huit caractères, sans expiration ni
  rotation, qui circulent dans les URL. Un token volé l'est pour
  toujours.

---

## 🟣 WORKFLOW PAIE (aval)

- **Journal MSA/Silae** : livré le 23/08. ✅
- **Export Silae (CSV)** : format et codes rubriques à confirmer avec
  l'expert-comptable.
- **Signature électronique** : Yousign Plus (déjà souscrit) — à
  clarifier contre l'ancienne piste « Desk RH/Silae ».
- **Nettoyage des jours « travaillée » sans heures** à la validation
  (requalification automatique).

---

## 🟤 ONBOARDING & SAISONNIERS

*(Détail : `vision_onboarding_saisonniers.md`)*

- **Formulaire self-service à token privé** : le futur collaborateur
  remplit ses infos, ce qui crée sa fiche. Documents et signature via
  Yousign, hors de l'appli.

---

## ⚫ ERGONOMIE / ADMIN

- **Renommage « Récap » → « Saisies »** — libellé **affiché
  uniquement**. ⚠️ Ne pas renommer les identifiants internes
  (`vue-recap`, `recap-tbody`, `chargerRecap`…) : beaucoup de lignes
  pour un gain nul.
- **Bouton admin « générer le jour manquant »** : rattraper une
  activation tardive sans passer par le SQL.
- **UX activation programmée** : poser une `date_activation` future
  devrait basculer en `en_attente` (sinon reste `inactif` et ne
  s'active jamais — piège récurrent).
- **Jours fériés** (demande Pauline) : architecture décidée, document
  d'amorçage v3 produit. Sortent du calcul automatique ; l'admin décide
  ligne par ligne ce qui est payé et à quel taux.
- **Onglet Paramètres** : admins, textes, jours spéciaux, mapping
  structures → sociétés. ⚠️ C'est aussi là que vivraient les seuils
  aujourd'hui en dur (10 jours pour « Sans renouvellement », 40 jours,
  quota de modifications) et le mémo des règles de contrats.
- ⚠️ **Vocabulaire « actif / inactif »** : ambigu — dans l'appli il
  qualifie un compte qui fonctionne, pas quelqu'un en poste.
  « Compte actif / Compte inactif » lèverait l'ambiguïté.

---

## ⚪ HYGIÈNE / DETTE TECHNIQUE

- **Le matricule Silae n'a rien à faire dans `historique_contrats`** —
  il identifie la personne, pas le contrat. Chaque écriture doit le
  transporter à l'identique sous peine de l'effacer, et le champ de la
  fiche identité est trompeur (écrasé par `rafraichir_fiche_collab`).
  ⚠️ Indolore aujourd'hui : aucun contrat n'en porte.
- **Les RPC ne sont pas versionnées** dans `sql/`. Perdre le projet
  Supabase, c'est perdre les fonctions. ⚠️ Le dépôt ne peut pas servir
  de source de vérité sur le schéma — seule la base le peut.
- **`heures_hebdo` n'accepte pas la virgule décimale** dans les Edge :
  `35,5` échoue. Le taux, lui, l'accepte depuis le 21/08.
- **`CREATE TABLE` non versionnés** (`jours`, `periodes`).
- **Ménage code mort** : `calculerPaiePeriode`, `grouperParSemaine`,
  `initPaie`, `rechargerDetailPaie`, fonctions GAS legacy.
  ⚠️ Chercher le **nom nu**, pas seulement `fn(` — les callbacks et
  références indirectes sont invisibles sinon.
- **Purger les données de test** dans `paie_detail` (DEC_2026_06).
- **`ZZTEST ATESTER` (COLL061)** — collaborateur de test, inactif. Peut
  servir de cobaye permanent ou être supprimé (`historique_contrats`
  puis `collaborateurs`, dans cet ordre).
- **`todayISO` en UTC** dans `index.html` → risque de mauvais jour en
  soirée. Le modèle correct (date locale) est déjà utilisé ailleurs.

---

## 📄 FOND / DOCUMENTATION

- **`PROCESSUS.md`** : règles métier et processus au fil de l'eau
  (cycle de vie d'une période, workflow paie, règles de saisie,
  activation).
- **Mémo contrats pour les admins** — rédigé, **à publier seulement
  quand les gestes décrits existent** (« Avenant » n'est pas codé, la
  désactivation automatique n'est pas branchée). Un mémo qui décrit
  autre chose que l'écran fait plus de mal que de bien.
- **Multi-tenant** : horizon lointain. Ne pas implémenter, ne pas se
  fermer la porte.

---

## Cap proposé

1. **Cron d'activation** — décidé, prêt, débloque l'automatisation.
2. **Contrôle de cohérence des totaux** — diagnostic, une heure.
3. **Surveillance externe** — dix minutes.
4. **Quick wins saisie collaborateur** — drummer cyclique, brouillon.
5. **Annualisation** — à concevoir avant de coder quoi que ce soit
   d'autre qui touche `heures_hebdo`.
