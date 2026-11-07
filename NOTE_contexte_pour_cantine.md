# Note de contexte — architecture & méthode

> À transmettre au projet Cantine. Décrit l'architecture de « Suivi des temps ·
> Chants de la Terre » et la façon de travailler qui s'est stabilisée dessus.
> État au 20/08/2026.

---

## 1. L'architecture de suivi-temps

### Le principe qui tient tout

**L'appli présente les faits, l'humain décide, les logiciels métier calculent.**
Elle produit des heures, jamais de la rémunération. Silae et la MSA font la
paie ; l'appli fournit ce qui se recopie.

C'est ce qui l'a gardée simple pendant six mois — et chaque fois qu'on a
envisagé de coder une règle métier complexe, on l'a écartée au profit d'un
écran de saisie.

### La stack

**Backend** — Supabase / PostgreSQL, région Frankfurt, offre Pro.
**Frontend** — trois fichiers HTML statiques servis par GitHub Pages, branche
`supabase`. Pas de framework, pas d'étape de build. On édite, on rafraîchit.
**Automatisation** — `pg_cron`, une fonction chef d'orchestre appelée chaque
nuit à 2 h.

### Les trois fronts

| Fichier | Public | Accès |
|---|---|---|
| `index.html` | les ~59 collaborateurs, sur téléphone | lien à token personnel |
| `manager.html` | les responsables d'équipe | token d'équipe |
| `admin-v2.html` | 3 administrateurs | token admin |

### La règle d'écriture — celle à reprendre telle quelle

> **Le rôle `anon` est en LECTURE SEULE. Toute écriture passe par une Edge
> Function en `service_role`, qui revalide les règles côté serveur sans jamais
> faire confiance au client.**

Treize Edge Functions aujourd'hui. Chacune : vérification du token admin par
une RPC, whitelist de colonnes, puis écriture. Une clé absente du corps de la
requête n'écrase jamais rien — c'est une propriété qu'on exploite
délibérément.

La clé publiable du front ne permet donc que de lire. C'est le modèle à
reconduire.

### Le modèle de données, en trois idées

**Le journal en ajout seul.** `historique_contrats` porte une ligne par
contrat, jamais écrasée. La situation actuelle se **calcule** en cherchant la
ligne qui couvre aujourd'hui ; la fiche du collaborateur n'est qu'un cache,
rafraîchi par une fonction dédiée. Un renouvellement clôt une ligne et en
ouvre une autre — il ne modifie jamais une date de fin, sinon on perd
l'information qu'il y a eu renouvellement.

**La double couche.** `paie_detail` porte deux jeux de colonnes : la photo de
ce que le collaborateur a saisi, et la version corrigée par l'admin. L'import
est différentiel avec `ignoreDuplicates` sur une clé unique — donc « un
recalcul n'écrase jamais un ajustement admin » est garanti par le **schéma**,
pas par une convention.

**Les périodes de paie**, générées et ouvertes automatiquement chaque nuit
(`planifiee → ouverte → gelee`), la clôture restant un geste admin. Deux
types coexistent, civil et décalé.

### Les RPC d'agrégation

Trois lectures volumineuses ont été remplacées par des fonctions SQL qui
agrègent en base. Le motif : **PostgREST tronque silencieusement à 1000
lignes**. Une lecture non bornée ne produit aucune erreur — elle renvoie des
données incomplètes, et l'écran affiche du faux sans le savoir.

C'est le piège le plus coûteux rencontré sur ce projet. À surveiller dès la
conception.

---

## 2. La méthode de travail

Quatre acteurs, des rôles stricts. C'est ce qui rend le rythme tenable pour
quelqu'un qui n'est pas développeur.

### Qui fait quoi

**Claude (le chat)** — conception, architecture, rédaction des prompts.
Ne touche à rien. Ne prétend jamais savoir dans quel état est le code.

**Claude Code (CC)** — les fichiers du dépôt, en local. Lit, écrit, commite.
**Aucun accès à la base.**

**Guillaume** — la base (SQL Editor Supabase), la validation de chaque diff,
les pushs, les déploiements. Le seul à voir l'ensemble.

**Terminal natif macOS** — les pushs Git et les déploiements d'Edge
Functions. Jamais confié à CC.

### Le cycle

1. On conçoit dans le chat jusqu'à l'accord.
2. Claude rédige un prompt pour CC.
3. CC exécute et **montre son diff en texte**.
4. Guillaume valide, teste, puis fait committer.
5. Push au Terminal, avec un token GitHub temporaire révoqué juste après.

**Un diff à la fois. Jamais de validation en bloc.**

### Les règles acquises à leurs dépens

**Un diff MONTRÉ n'est pas un diff APPLIQUÉ.** Incident réel : plusieurs
tours de recette sur du code qui n'existait pas, puis 124 lignes importées par
erreur en production. Tout prompt de modification se termine désormais par
« montre-moi la ligne telle qu'elle est DÉSORMAIS et confirme que le fichier
EST modifié ».

**Un inventaire n'a pas plus d'autorité qu'un diff montré.** Deux entrées sur
quatre d'un tableau produit par CC se sont révélées fausses. Toute entrée qui
commande un correctif se revérifie sur le corps complet.

**Un contrôle de « fonction morte » doit chercher le nom NU.** Une fonction a
figuré dans deux inventaires comme morte : elle était passée en callback,
`forEach(fn)`, sans parenthèses. La supprimer aurait tué toute la page.

**CC ne montre pas de code par `cat` ni par l'outil Read** — ces sorties
n'arrivent pas jusqu'à l'humain. Il doit ÉCRIRE les extraits dans son message.

**Faire PROPOSER CC avant d'écrire**, dès qu'un diff touche une fonction
partagée. Trois pièges évités ainsi en une journée.

**Jamais `git add .`** — on nomme toujours les fichiers.

**Toute recette en console se fait sur localhost**, jamais sur la production.
Et avant tout test : `<fonction>.toString().includes('<marqueur>')` pour
savoir quelle version est chargée.

**Edge avant front, jamais l'inverse.** L'ordre est non commutatif : le
contraire donne un état où plus rien ne s'écrit, sans erreur visible.

### La documentation

Trois fichiers vivants, aux rôles distincts :

- **`CLAUDE.md`** — les décisions, le *pourquoi*. Jamais l'état du code,
  jamais de numéro de ligne.
- **`SCHEMA_REEL.md`** — l'état de la base.
- **`FEUILLE_DE_ROUTE.md`** — ce qui reste à faire, plus deux sections
  ajoutées après coup et qui se sont révélées les plus utiles :
  **« ce qu'il ne faut pas changer »** et **« méthode »**.

> Une documentation fausse est pire qu'une documentation absente : on s'y fie.
> Plusieurs fichiers affirmaient le contraire de la base ; les corriger a pris
> une journée. La règle est désormais qu'un document se corrige au moment où
> l'on constate l'écart, jamais « plus tard ».

### Le rythme

Chaque chantier commence par une **passe de lecture** — CC lit le code
existant et le réécrit en texte — avant toute conception. Et se termine par un
**document d'amorçage** autonome, à coller dans un chat neuf.

Les longues conversations dérivent : les erreurs de fin de session sont
mesurablement plus nombreuses. Un chat par chantier, avec son document
d'amorçage, est la parade.

---

## 3. Ce qui vaut d'être repris tel quel

- La règle d'écriture (`anon` en lecture, Edge en `service_role`).
- Le journal en ajout seul pour tout ce qui a une histoire.
- La séparation stricte des rôles chat / CC / humain / terminal.
- Les documents d'amorçage entre chantiers.
- Et le principe de fond : **l'appli présente, l'humain décide.**
