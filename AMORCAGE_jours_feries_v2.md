# Amorçage — Chantier « jours fériés & journées de solidarité » (v2)

> Document de reprise. Conception cadrée, **non commencée côté code**.
> Prochain geste concret : une capture d'écran du formulaire MSA (§5).
> Ce document est autonome : rien à rechercher dans l'historique des chats.

---

## 1. Cadre projet

**Appli** : « Suivi des temps · Chants de la Terre » — suivi des heures et
préparation de paie pour une exploitation agricole (~55 collaborateurs,
3 structures : SCEA, SAS, SARL « 6 Saveurs »).

**Stack**
- Backend : Supabase / PostgreSQL, projet `oldkmapumqnibdcniecd` (Frankfurt).
  Toutes les écritures authentifiées passent par des Edge Functions.
- Frontend : GitHub Pages, branche `supabase`, dépôt
  `chantsdelaterre/suivi-temps`. Trois fichiers : `index.html` (collab),
  `admin-v2.html` (admin), `manager.html` (responsable).
- Agent local : Claude Code (CC) dans `~/suivi-temps`.
- Ancien système (Google Apps Script + Sheets, branche `main`) : prod de
  secours pour rollback uniquement. **Ne pas utiliser.**

**Méthode (règle du 17/07)**
- Conception dans le chat → accord → prompt à CC qui exécute localement →
  Guillaume valide chaque diff et pousse manuellement.
- Le chat ne prétend **jamais** connaître l'état du code sans un grep CC.
- `CLAUDE.md` porte les décisions (le *pourquoi*), jamais l'état du code,
  jamais de numéros de ligne. `FEUILLE_DE_ROUTE.md` porte le reste à faire.
- Un diff à la fois, jamais de validation en bloc.
- **CC ne doit utiliser NI `cat` NI l'outil Read pour montrer du code** : ces
  sorties n'arrivent pas jusqu'à Guillaume. Il doit ÉCRIRE les extraits en
  texte. ⚠️ Le format « Update(fichier) » que CC affiche avant son diff mélange
  lignes supprimées et conservées sans marqueur — **il n'est pas fiable pour
  juger**. Seul un extrait verbatim l'est.
- **Répartition des rôles** : CC = les fichiers du dépôt. Guillaume = la base
  (SQL Editor Supabase). CC n'a aucun accès à la base.
- **Jamais `git add .`** — on nomme toujours les fichiers explicitement.
- **Le push reste au Terminal natif** (token classic temporaire, scope `repo`,
  révoqué immédiatement après). Jamais confié à CC.

---

## 2. Le besoin

Deux natures de dates à définir **par année** :

- **Jours fériés.** ⚠️ **Alsace-Moselle : 13 jours fériés légaux**, pas 11
  (Vendredi Saint et 26 décembre en plus des onze nationaux).
- **Journées de solidarité** — **PAS fériées** au regard du droit du travail.
  Jour travaillé normalement, sans rémunération supplémentaire.

Deux usages :
1. **Repérer ces dates** dans les tableaux et sur le relevé (badge).
2. **Produire les éléments de paie** que l'admin ressaisit — **sur le site MSA
   pour les TESA**, dans Silae pour le reste.

**Population réellement concernée : les TESA et CDD courts.** Les CDI sont
annualisés, donc hors sujet. C'est précisément la population qui passe par la
MSA — d'où l'importance du §5.

---

## 3. LA décision structurante : la règle n'est PAS codable

Une note de synthèse sur le traitement des JF en TESA (accord agricole
alsacien, production fruits et légumes) a été produite lors de la conception.
**Elle s'est corrigée deux fois et a donné trois réponses différentes** à la
même question — d'abord « 7 h + heures à 125 % », puis « 200 % au total », puis
« heures réellement travaillées au taux normal, sans ajout ». Elle se conclut en
recommandant une validation écrite par le gestionnaire de paie sur
l'articulation d'une majoration de 15 % avec l'exception fruits et légumes.

> **CONSÉQUENCE ARCHITECTURALE : cette règle ne doit JAMAIS être codée en dur.**
> Si trois lectures d'un même texte conventionnel donnent trois résultats,
> l'appli qui en figerait un se tromperait sur les deux autres — silencieusement.

L'appli ne décide rien. Elle **présente les faits, l'admin écrit la réponse**.

### État de la règle tel que compris (à faire valider, NE PAS coder)

| Situation | Traitement |
|---|---|
| JF sur un jour de repos | Rien à ajouter |
| JF chômé — au moins 2 mois de présence | Heures prévues payées, taux normal |
| JF chômé — moins de 2 mois | Indemnité plafonnée à 3 % du brut mensuel |
| Saisonnier, 3 mois cumulés sur plusieurs contrats | Heures prévues payées |
| JF **travaillé** en fruits et légumes | Heures réellement travaillées, taux normal |
| 1er mai chômé | Heures prévues, sans condition d'ancienneté |
| 1er mai travaillé | Heures à 200 % |

Condition annexe : présence le dernier jour travaillé avant et le premier jour
travaillé après, sauf absence autorisée.

---

## 4. Modèle de données arrêté

### 4.1 Table `jours_feries` (référence, ~13-15 lignes par an)

| colonne | type | note |
|---|---|---|
| `date_jour` | date | clé |
| `nature` | text | `'ferie'` ou `'solidarite'` |
| `libelle` | text | « 14 juillet », « Vendredi Saint » |
| `taux_defaut` | numeric | **proposé, jamais imposé** — voir 4.2 |

Écriture par Edge Function, lecture `anon`.

**Génération assistée** : bouton « générer l'année N » → les 13 dates
(8 fixes, 3 dérivées de Pâques par algorithme déterministe, + Vendredi Saint
et 26 décembre pour l'Alsace-Moselle). L'admin ajoute ensuite la journée de
solidarité, qui relève d'un choix d'employeur.

### 4.2 ⚠️ Le taux ne vit PAS sur le calendrier — correction v1

Une version antérieure faisait du taux une propriété de la date. **C'est faux.**
Le taux dépend de la **personne** : chômé ou travaillé, deux mois de présence
ou moins, trois mois cumulés, 1er mai. Le calendrier ne porte qu'un **défaut
proposé**. L'admin décide ligne par ligne.

### 4.3 Table fille de `recap_paie` — N lignes par (période, collab, date)

| colonne | source |
|---|---|
| `periode_id` | — |
| `collab_id` | — |
| `date_jour` | — |
| `heures` | saisie admin |
| `taux` | pré-rempli depuis le calendrier, **modifiable** |

Exemple :

```
CIVIL_2026_05 | COLL014 | 01/05 | 7,00 | 200
CIVIL_2026_07 | COLL014 | 14/07 | 7,00 | 100
```

**Plusieurs lignes possibles pour une même date.** Zéro ligne si rien n'est dû —
table sparse, la majorité des collaborateurs n'y figurent pas.

**Pourquoi une table fille et pas des colonnes** : le signal d'alerte, c'est la
colonne numérotée (`heures_125`, `heures_200`…). Dès qu'on énumère des colonnes
de même nature, une liste veut sa table. Même schéma qu'`historique_contrats`.

Le taux est **recopié et figé** à la validation, comme les totaux de
`recap_paie` : corriger le calendrier ensuite ne doit jamais modifier une
période close.

### 4.4 Ce qui n'est PAS touché

`jours` et `paie_detail` restent intacts. Pas d'`ALTER TABLE`, pas d'extension
de whitelist sur `ajuster-paie`, **`importer-paie` jamais modifié**. Sur la
ligne du jour : un simple badge « Férié » issu du calendrier, aucune donnée
stockée.

### 4.5 Pas de type de jour `FERIE`

Le badge vient du calendrier, les heures vivent dans le bloc. Le type du jour
reste `travaillée`.

> Conséquence : **pas besoin de rouvrir** la section « Règles par type de jour
> (VERROUILLÉES) » de `CLAUDE.md`.

### 4.6 Le cas des 3 % est HORS PÉRIMÈTRE

Indemnité en euros, calculée sur le taux horaire, plafonnée sur un cumul
mensuel. Trois données absentes de l'appli : `taux_horaire` (question ouverte
de `CLAUDE.md` — dans l'appli ou chez Silae ?), le brut du mois, et le cumul
mensuel.

**Décision : aucune ligne dans le bloc.** L'admin sait que ce collaborateur
relève des 3 %, il ne saisit pas d'heures. Le cas se traite ailleurs.
Cohérent avec « heures sup hors moteur, trop particulier ».

### 4.7 Simplification apportée par la règle fruits et légumes

Si un JF **travaillé** se paie aux seules heures réellement travaillées au taux
normal, c'est **un jour ordinaire** : les heures sont déjà dans
`heures_travaillees` via les créneaux. **Aucune ligne à créer.**

Le bloc ne sert donc que dans trois situations : JF **chômé** indemnisé
(heures non travaillées, donc absentes de `paie_detail`), **1er mai travaillé**
(le supplément au-delà du taux normal), **1er mai chômé**.

Beaucoup moins de saisies que redouté.

### 4.8 Journée de solidarité : rien à calculer

Elle entre au calendrier et s'affiche, point. Le besoin de vérifier une fois
par an que chacun a fait ses 7 h est un **compteur annuel**, même famille que
le compteur de CP — chantier séparé déjà noté dans `CLAUDE.md`.

---

## 5. ⚠️ PROCHAIN GESTE : le formulaire MSA

**Les TESA ne passent pas par Silae. La paie se fait sur le site de la MSA.**

Un formulaire MSA impose ses champs, leurs intitulés et leurs unités (heures ou
euros). Ce que le bloc doit produire n'est donc pas « ce qui nous paraît
clair », mais **exactement ce que le formulaire réclame**.

> **MÉTHODE : concevoir à rebours du formulaire.**
> Geste concret : à la prochaine saisie TESA sur msa.fr, **une capture d'écran
> de l'écran de saisie des éléments de rémunération**. On voit les champs
> réels, on dessine le bloc pour les remplir un à un, dans le même ordre.

Cette capture peut absorber une partie des questions du §6 : si le formulaire
ne prévoit qu'une ligne « heures » et une ligne « autres rémunérations », la
question du taux se règle avant la saisie, pas dans l'appli.

---

## 6. Questions ouvertes — pour Pauline / le gestionnaire de paie

1. **Quels champs le formulaire MSA attend-il pour un jour férié ?** (Voir §5 —
   la capture d'écran répond en partie.)
2. **La majoration de 15 %** pour saisonniers non mensualisés de moins de deux
   mois : comment s'articule-t-elle avec l'exception fruits et légumes ? La note
   source la signale comme mal rédigée et demande une validation écrite.
3. **Un JF chômé indemnisé** produit-il une ligne distincte, ou est-il noyé dans
   les heures normales ?
4. **La journée de solidarité** laisse-t-elle une trace côté MSA / Silae ?
5. **Le seuil d'ancienneté** : 2 mois de présence (accord alsacien) vs 3 mois
   cumulés sur plusieurs contrats (code du travail). Confirmer l'articulation.

---

## 7. Points de conception restants

- **Entête ou pied de RIH ?** Le modèle de données est identique — c'est un
  choix d'affichage. En entête : une déclaration à faire avant d'examiner le
  détail. En pied : une synthèse de ce qu'on vient de lire. Recommandation :
  **le pied**, puisque l'admin doit d'abord regarder les jours pour décider.
  À trancher par Guillaume.
- **Le bloc pré-liste** les dates fériées de la période, avec le taux par
  défaut du calendrier. Seules les heures sont vides.
- **Action groupée** : si le volume de saisie s'avère pénible, prévoir un
  « 7 h à tous les TESA de cette période ». À concevoir **en même temps** que
  l'écran, pas après. (Moins critique depuis §4.7.)
- **Le total du RIH** : les heures fériées payées non travaillées s'ajoutent-
  elles au total affiché au salarié ?
- **Garde-fou à la validation** : avertir si la période contient une date fériée
  absente du calendrier. Le calendrier doit exister **avant la validation** —
  pas avant l'import. Remplir l'année en décembre suffit, et même en cours de
  mois. Mais après validation `recap_paie` est figé : remplir ensuite ne
  rattrape rien.
- **Deux onglets distincts** : **Paramètres** (calendrier, écriture) et **Aide**
  (règles métier, lecture seule). Ne pas les mélanger — dans six mois on ne
  saurait plus lequel fait foi.
- **Onglet Aide** : doublonne avec `CLAUDE.md` et `PROCEDURES_md`. Lit-elle un
  fichier du dépôt, ou assume-t-on deux textes distincts (l'un pour Guillaume et
  Claude, l'autre pour Pauline et Elsa) ?
- **Piste pour plus tard** : la condition de présence le dernier jour travaillé
  avant et le premier après est **le seul élément dérivable** de toute la règle —
  l'appli a toutes les saisies. Hors périmètre (définir « dernier jour
  travaillé » n'est pas trivial), mais à noter.
- **Vestige à vérifier par grep** : un type `ferie` existait dans les mappings
  de libellés de l'ancien système GAS (`{ travaille, conge, absence, ferie }`).
  Vérifier s'il survit — du code mort affichant « Férié » pour un type
  inexistant est un piège.
- **Collision possible** : la note du module Cantine prévoit une table
  `fermetures` globale incluant les jours fériés. Deux endroits sauraient quels
  jours sont fériés, donc deux endroits peuvent diverger.

---

## 8. Séquence de travail proposée

1. Capture du formulaire MSA (§5) + réponses aux questions du §6.
2. Conception du bloc, à rebours des champs MSA.
3. `CREATE TABLE` calendrier + table fille (Guillaume, SQL Editor).
   ⚠️ **`CREATE FUNCTION` re-grante silencieusement `EXECUTE` à `public`** —
   révoquer explicitement après toute création de fonction.
4. Onglet Paramètres : écran calendrier + génération de l'année.
5. Edge Function d'écriture du calendrier + extension de `valider-recap`.
6. Affichage : badges dans les tableaux, bloc sur le RIH.
7. Resynchroniser `SCHEMA_REEL.md`.
8. Recette, commits groupés, push manuel.

**Rappel d'ordre de déploiement** : Edge avant front, jamais l'inverse.
L'inverse donne un état où plus rien ne s'écrit, sans erreur visible.

---

## 9. Hors chantier mais à connaître

- **Le lot 2 (clôture partielle de paie par collaborateur) est prioritaire** et
  en cours : sa passe 2 de lecture CC était le prochain geste. Document
  d'amorçage séparé.
- `ajuster-paie` et `valider-recap` n'ont **aucun contrôle de statut de
  période** : une période clôturée reste modifiable. Trou préexistant.
- **Règle de pagination** (lot « impression en lot ») : trier sur une colonne à
  ex æquo massifs produit un ordre indéterminé entre deux pages. On pagine sur
  une colonne UNIQUE (`id`) ; l'ordre métier se refait en mémoire après
  agrégation.
- **Fenêtre pop-up** : ouvrir `window.open` AVANT les lectures asynchrones,
  sinon Chrome bloque après les `await`.
- `admin.html` (ancien « Backoffice ») coexiste toujours sur GitHub Pages —
  risque de double backoffice, à éliminer.
- Le token admin circule en clair dans l'URL. Rotation à prévoir.
- Périodes de référence : `DEC_2026_07` (clôturée, 860 lignes, 46 ajustements
  admin — témoin d'intégrité), `CIV_2026_06` (clôturée manuellement en SQL,
  vide), `CIV_2026_07` (clôturée, 28 collabs), `DEC_2026_08` (ouverte).
  ⚠️ L'écran affiche « CIVIL_2026_07 » là où la base contient « CIV_2026_07 » —
  dérive de libellé non élucidée.
