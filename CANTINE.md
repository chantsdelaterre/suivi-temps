# CANTINE.md — décisions et pourquoi

> Décisions actées pour le projet cantine. Jamais l'état du code — voir
> `SCHEMA_CANTINE.md` pour ça. Un fichier se corrige au moment où l'on
> constate l'écart, jamais plus tard.

---

## Cadrage général

**Pas de retenue sur bulletin de salaire.** Avis du comptable. La
facturation est mensuelle, globale, hors application. L'appli produit un
décompte de repas, elle n'enregistre aucune vente, aucun règlement, aucune
facture — donc aucune obligation liée aux logiciels de caisse.

**Tarif 4,50 € HT, TVA 10 %.** Montants stockés en centimes, jamais en
flottants.

**Schéma `cantine` dans le projet Supabase existant**, pas un projet
séparé. Clés étrangères vers le référentiel collaborateurs
(`public.collaborateurs`, clé `collab_id` en `text` — pas `uuid`), aucune
duplication de l'identité.

## Le modèle : deux axes qui ne se mélangent pas

```
statut  ∈ prevu | annule | en_attente | engage | refuse
origine ∈ routine | manuelle | invite
hors_delai : booléen
```

Le décompte de facturation s'appuie sur l'**engagé**, pas sur le **pris** :
le repas est cuisiné, l'absent le doit. Pas de pointage au chantier A — le
journal d'événements suffit aux litiges à ce volume.

**Deadline la veille à 10h, contrôlée exclusivement côté serveur**, jamais
dans le JS de la page. Passé la deadline, une demande n'est pas refusée
automatiquement : elle passe en `en_attente`, Hervé arbitre.

**Routine hebdomadaire en opt-in strict.** Rien n'est généré par défaut —
c'est le collaborateur qui crée sa routine, jamais l'inverse.

## Pourquoi `convives` et pas `collaborateurs`

La table est générique dès le chantier A (`type` : `salarie`, `externe`,
`invite`) parce que le type `externe` arrivera au chantier C. La nommer
`collaborateurs` aurait imposé une migration de table à ce moment-là.
**Ne jamais la renommer.**

Les invités rares ne sont pas des lignes `convives` : un nombre et un
régime optionnel sur `inscriptions`, sans nom, imputés au convive hôte. Le
type `invite` de `convives` est prévu pour un usage individuel plus tard,
pas peuplé au chantier A.

## Pourquoi les régimes sont une table de référence, pas un champ libre

**On enregistre le quoi, jamais le pourquoi.** Un champ libre inviterait à
justifier un régime — ce qui reviendrait à constituer un fichier de
données de santé ou de pratique religieuse sans le vouloir. La table
`regimes` est fermée et amorcée avec quatre codes seulement.

## Pourquoi `inscriptions_evenements` est bloquée en écriture, y compris pour `service_role`

C'est la seule pièce justificative du décompte en cas de litige. Un
`GRANT`/`REVOKE` n'aurait pas suffi : `service_role` bypasse RLS par
défaut, donc a accès en écriture à tout. L'append-only est donc imposé par
un trigger qui refuse `UPDATE`/`DELETE` sans condition, quel que soit
l'appelant — vérifié en conditions réelles le 16/09 (désactivation
temporaire nécessaire pour nettoyer une ligne de test, puis réactivation
immédiate).

## Pourquoi RLS est activée à la création de chaque table, pas après coup

Décision prise en cours de chantier A, pas dans l'amorce initiale : pour
qu'aucune table n'existe, même une minute, sans RLS active. Le principe est
le refus par défaut tant qu'aucune policy n'autorise explicitement — donc
l'ordre `CREATE TABLE` → `ENABLE ROW LEVEL SECURITY` → policies, jamais
l'inverse.

## Pourquoi `anon` en lecture seule a été vérifié par l'API, pas seulement en base

Une policy RLS qui existe en base ne prouve pas qu'elle est appliquée : il
manquait encore que le schéma `cantine` soit coché dans *Exposed schemas*
(Data API), sans quoi PostgREST ne sert rien du tout, policy ou pas. Testé
le 16/09 en conditions réelles via `curl` avec la clé `anon` : lecture
réussie sur `cantine.regimes`, écriture refusée
(`permission denied for table regimes`).

## Ce qui reste ouvert (sans effet sur le schéma actuel)

- Rendez-vous comptable, nécessaire pour le chantier B : confirmation du
  taux à 10 %, fait générateur de la TVA sur facture mensuelle, absence
  d'avantage en nature à 4,95 € TTC, invités refacturés à une entreprise
  tierce.
- Trois questions à Hervé : annonce du décompte sur l'engagé, validation
  des invités, rythme d'arbitrage.
- Facture mensuelle globale ou par convive — effet sur le contenu de
  l'export au chantier B, pas sur le schéma.
- Filtrage RLS par convive : aujourd'hui `anon` lit toutes les lignes de
  toutes les tables, pas seulement les siennes. Non bloquant à ce volume
  (6 à 15 couverts/jour, 59 collaborateurs).

## Pas encore fait

- Pas d'écran admin (Guillaume utilise le SQL Editor).
- Pas d'Edge Function écrite (les écritures `service_role` restent à
  construire — chantier suivant).
