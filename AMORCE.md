# AMORCE — Cantine, chantier A, étape 3 : les Edge Functions d'écriture

État au 16/09/2026. À coller dans un chat neuf.

---

## 1. Où on en est

Étape 2 terminée et documentée : schéma `cantine` créé, dix tables, RLS
activée à la création (pas après coup), policies de lecture `anon` posées
et **vérifiées en conditions réelles** (pas seulement en base) via `curl`
sur l'API REST — lecture réussie, écriture refusée.

`SCHEMA_CANTINE.md` et `CANTINE.md` écrits, relus intégralement (début et
fin, pas seulement un extrait), poussés sur `supabase`.

Étape 3, celle qui commence : écrire les Edge Functions qui permettent
d'écrire dans le schéma `cantine`. Rien n'écrit encore — `anon` est en
lecture seule, aucune fonction n'existe. Les pages front (`collab.html`,
`gestion.html`) ne sont pas non plus commencées.

## 2. Le projet en six lignes

Application de réservation de repas pour la cantine de Chants de la
Terre. 59 collaborateurs, 6 à 15 couverts par jour. Extension de
l'application Suivi des temps, schéma `cantine` du même projet Supabase.

L'appli produit un décompte de repas. Elle n'enregistre aucune vente,
aucun règlement, aucune facture. La facturation est mensuelle, globale,
hors application.

## 3. Ce qui est décidé et clos

Repris de l'étape 2, toujours valable :

1. Pas de retenue sur bulletin de salaire.
2. Facturation mensuelle globale, hors appli.
3. Tarif 4,50 € HT, TVA 10 %, historisé dans `tarifs` (jamais écrasé).
4. Schéma `cantine`, FK vers `public.collaborateurs.collab_id`
   (`text`, pas `uuid` — vérifié en base le 16/09).
5. Écriture par Edge Functions en `service_role` uniquement. `anon` en
   lecture seule — vérifié via l'API réelle, pas seulement en base.
6. Deadline la veille à 10h, contrôlée exclusivement côté serveur.
7. Routine hebdomadaire en opt-in strict.
8. Après la deadline, une demande passe en `en_attente`, jamais refusée
   automatiquement.
9. Décompte assis sur l'`engage`, pas sur le pris.
10. Pas de pointage, pas d'écran admin en chantier A.
11. Régimes alimentaires : table de référence fermée, quatre codes, pas
    de champ libre.
12. Invités rares : colonnes sur `inscriptions` (`nombre_invites`,
    `regimes_invites`), pas de ligne `convives` dédiée.
13. RLS activée **à la création** de chaque table, jamais après coup.
14. `inscriptions_evenements` en append-only imposé par trigger — bloque
    `UPDATE`/`DELETE` même pour `service_role`, qui bypasse RLS mais pas
    un trigger.

## 4. Ce qui est fait

Le schéma complet existe et est testé — voir `SCHEMA_CANTINE.md` pour le
détail colonne par colonne, `CANTINE.md` pour le pourquoi de chaque
décision structurante. Ne pas reconstituer ces documents de mémoire, les
lire.

## 5. Ce qui reste à faire à l'étape 3

Edge Functions à écrire, dans cet ordre de dépendance logique :

1. **`creer-routine`** — un convive crée ou modifie sa routine
   hebdomadaire. Vérifie que le convive existe et est actif.
2. **`inscrire`** — inscription manuelle ou générée par routine. Doit
   calculer `hors_delai` côté serveur (deadline = veille 10h),
   **jamais fait confiance au client**. Statut `prevu` si dans les
   délais, `en_attente` si hors délai.
3. **`desinscrire`** — même logique de délai, statut `annule` ou
   `en_attente` selon le timing.
4. **`generer-inscriptions-routine`** — fonction chef d'orchestre,
   appelée périodiquement (cron), matérialise les lignes S+1 depuis les
   routines actives. Ne recalcule jamais à la volée à l'affichage.
5. **`arbitrer`** — Hervé valide ou refuse une inscription
   `en_attente` → `engage` ou `refuse`. Réservée au token admin.
6. **`engager-jour`** — fige les inscriptions `prevu` d'une date donnée
   en `engage`, y attache `tarif_ht_centimes` et `taux_tva` depuis
   `tarifs` (le tarif en vigueur à cette date, pas forcément le
   dernier).

Chaque écriture métier (inscrire, désinscrire, arbitrer, engager) doit
aussi insérer une ligne dans `inscriptions_evenements` — c'est la seule
pièce justificative en cas de litige, elle ne se déduit pas après coup.

## 6. Ce qui est ouvert (sans effet sur les Edge Functions)

- Rendez-vous comptable (chantier B) : taux TVA, fait générateur,
  avantage en nature, invités refacturés à un tiers.
- Trois questions à Hervé : annonce du décompte sur l'engagé, validation
  des invités, rythme d'arbitrage.
- Facture mensuelle globale ou par convive (chantier B).
- Filtrage RLS par convive : `anon` lit aujourd'hui toutes les lignes,
  pas seulement les siennes. Non bloquant à ce volume, à revoir si ça
  devient gênant.

## 7. Pièges identifiés, à ne pas réapprendre

**PostgREST tronque silencieusement à 1000 lignes.** Sans effet direct
sur les Edge Functions d'écriture, mais à garder en tête pour toute
fonction de lecture agrégée plus tard.

**Un rapport de CC n'a d'autorité que sur ce qu'il montre, pas sur ce
qu'il affirme.** Demander systématiquement le texte écrit dans la
réponse (jamais `cat` ni l'outil Read), et pour un fichier de référence,
vérifier **le début ET la fin**, pas un seul des deux — un rapport peut
être vrai sur l'un et faux sur l'autre en même temps. Ça s'est produit
le 16/09 sur `CANTINE.md` : la fin était juste, le début manquait.

**Des triples backticks imbriqués cassent un bloc markdown.** Si un
prompt destiné à CC contient lui-même un bloc ``` (par exemple un
extrait SQL ou un schéma en texte), envelopper le prompt entier dans
quatre backticks ```` au lieu de trois — sinon le premier ``` interne
referme le bloc englobant et coupe le texte en deux, silencieusement.

**`service_role` bypasse RLS mais pas un trigger.** Pour imposer un
append-only réellement infranchissable (`inscriptions_evenements`), un
`GRANT`/`REVOKE` ne suffit pas — il faut un trigger qui refuse sans
condition.

**Désactiver un trigger pour nettoyer un test doit être suivi d'une
réactivation immédiate**, dans le même envoi si possible — ne pas
laisser un trigger de sécurité désactivé entre deux messages.

**Une policy RLS en base ne prouve pas qu'elle s'applique.** Il faut
aussi que le schéma soit coché dans *Exposed schemas* (Data API), et
idéalement un test réel via `curl` avec la clé `anon` — lecture et
écriture, pas seulement l'une des deux.

**`collab_id` est du texte, pas un uuid.** Toute nouvelle table qui
référence `public.collaborateurs` doit utiliser `collaborateur_id text`,
jamais `uuid`.

**Edge avant front, jamais l'inverse.**

**Jamais `git add .`** — on nomme toujours les fichiers.

## 8. Les rôles

**Claude dans le chat** — conception, architecture, rédaction des
prompts pour CC. Ne touche à rien, ne prétend jamais savoir dans quel
état est le code — vérifie plutôt (GitHub brut, requêtes SQL données à
Guillaume) quand c'est possible avant d'écrire quoi que ce soit.

**Claude Code** — les fichiers du dépôt, en local. Aucun accès à la
base.

**Guillaume** — la base via le SQL Editor Supabase, la validation de
chaque diff, les pushs, les déploiements. Le seul à voir l'ensemble.
N'est pas développeur : explications sans jargon inutile, décisions
justifiées, pas assénées.

**Terminal natif macOS** — les pushs Git et les déploiements d'Edge
Functions. Jamais confié à Claude Code.

Un diff à la fois. Jamais de validation en bloc.

## 9. Documents

- `CANTINE.md` — les décisions et le pourquoi. Créé, poussé le 16/09.
- `SCHEMA_CANTINE.md` — l'état réel de la base. Créé, poussé le 16/09.
  À régénérer par introspection après toute nouvelle migration.
- `regles-metier.md` — existant, non retouché à l'étape 2.
- `FEUILLE_DE_ROUTE.md` — ce qui reste à faire, plus « ce qu'il ne faut
  pas changer » et « méthode ». Non retouché à l'étape 2 — à mettre à
  jour au fil de l'étape 3.
- `AMORCE.md` — ce document, écrasé à chaque nouveau chantier.

Une documentation fausse est pire qu'une documentation absente. Un
document se corrige au moment où l'on constate l'écart, jamais plus
tard.

## 10. La prochaine action

Concevoir la première Edge Function, `creer-routine` : son contrat
(entrée attendue, whitelist de colonnes, vérifications avant écriture),
avant tout code. Comme pour le schéma, écrire le prompt pour CC une
fois la conception actée dans le chat, pas avant.
