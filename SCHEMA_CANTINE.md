# SCHEMA_CANTINE — schéma `cantine` (Supabase)

> Généré le 16/09/2026 depuis `information_schema.columns` et
> `information_schema.table_constraints` en base (projet `oldkmapumqnibdcniecd`).
> Colonnes et contraintes intégralement confirmées en base — aucune reprise
> depuis les fichiers `sql/` du dépôt.

---

## Couverture

Dix tables, toutes créées le 16/09/2026, chantier A du projet cantine.

## `convives`

Générique — pas seulement les salariés. Le type `externe` sera peuplé au
chantier C. Ne jamais renommer en `collaborateurs`.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `uuid` | NON | `gen_random_uuid()` |
| `type` | `text` | NON | |
| `collaborateur_id` | `text` | oui | |
| `nom` | `text` | oui | |
| `actif` | `boolean` | NON | `true` |
| `cree_le` | `timestamptz` | NON | `now()` |

Contraintes : `type IN ('salarie','externe','invite')` ; FK
`collaborateur_id → public.collaborateurs.collab_id` ; CHECK
`convives_coherence_type` (salarié ⇒ `collaborateur_id` non nul, externe ⇒
`nom` non nul).

## `regimes`

Table de référence, amorcée avec 4 lignes.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `code` | `text` | NON | (PK) |
| `libelle` | `text` | NON | |
| `actif` | `boolean` | NON | `true` |
| `ordre` | `integer` | NON | `0` |

## `convives_regimes`

Liaison, plusieurs régimes par convive.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `convive_id` | `uuid` | NON | (PK, FK → `convives.id`) |
| `regime_code` | `text` | NON | (PK, FK → `regimes.code`) |

## `jours_servis`

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `date` | `date` | NON | (PK) |
| `servi` | `boolean` | NON | `true` |
| `motif` | `text` | oui | |

## `tarifs`

Historisé — jamais écrasé, une nouvelle ligne ouverte à chaque changement.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `uuid` | NON | `gen_random_uuid()` |
| `categorie` | `text` | NON | `'standard'` |
| `montant_ht_centimes` | `integer` | NON | |
| `taux_tva` | `numeric` | NON | |
| `date_debut` | `date` | NON | |
| `date_fin` | `date` | oui | |

Contraintes : `montant_ht_centimes >= 0` ; `tarifs_periode_valide`
(`date_fin IS NULL OR date_fin >= date_debut`).

## `routines`

Opt-in strict — rien n'est généré par défaut.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `uuid` | NON | `gen_random_uuid()` |
| `convive_id` | `uuid` | NON | FK → `convives.id` |
| `jour_semaine` | `smallint` | NON | |
| `actif` | `boolean` | NON | `true` |
| `date_debut` | `date` | NON | `CURRENT_DATE` |
| `date_fin` | `date` | oui | |
| `cree_le` | `timestamptz` | NON | `now()` |

Contraintes : `jour_semaine BETWEEN 1 AND 7` (1 = lundi) ;
`routines_periode_valide`.

## `inscriptions`

La table centrale.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `uuid` | NON | `gen_random_uuid()` |
| `convive_id` | `uuid` | NON | FK → `convives.id` |
| `date_repas` | `date` | NON | |
| `statut` | `text` | NON | |
| `origine` | `text` | NON | |
| `hors_delai` | `boolean` | NON | `false` |
| `nombre_invites` | `integer` | NON | `0` |
| `regimes_invites` | `text[]` | oui | |
| `tarif_ht_centimes` | `integer` | oui | |
| `taux_tva` | `numeric` | oui | |
| `cree_le` | `timestamptz` | NON | `now()` |
| `modifie_le` | `timestamptz` | NON | `now()` |

Contraintes : `statut IN ('prevu','annule','en_attente','engage','refuse')` ;
`origine IN ('routine','manuelle','invite')` ; `nombre_invites >= 0` ;
UNIQUE `(convive_id, date_repas)`.

⚠️ **`tarif_ht_centimes` et `taux_tva` restent NULL jusqu'à l'engagement** —
figés à ce moment-là, côté Edge Function (logique non présente dans ce
schéma).

⚠️ **`regimes_invites` n'a pas de contrainte FK native** (impossible sur un
tableau en Postgres). Validé à l'écriture par le trigger
`inscriptions_verifier_regimes_invites`, testé en conditions réelles le
16/09 : rejette un code inconnu, accepte un code valide.

## `inscriptions_evenements`

Append-only — seule pièce justificative du décompte.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `uuid` | NON | `gen_random_uuid()` |
| `inscription_id` | `uuid` | NON | FK → `inscriptions.id` |
| `horodatage` | `timestamptz` | NON | `now()` |
| `acteur` | `text` | NON | |
| `statut_avant` | `text` | oui | |
| `statut_apres` | `text` | NON | |

⚠️ **UPDATE et DELETE bloqués par trigger** (`evenements_interdire_update`),
quel que soit le rôle appelant — y compris `service_role`, qui bypasse RLS
mais pas ce trigger. Testé en conditions réelles le 16/09 dans les deux cas.
Pour corriger une ligne de test, il faut désactiver le trigger
explicitement (`ALTER TABLE ... DISABLE TRIGGER`), puis le réactiver
aussitôt.

## `clotures`

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `uuid` | NON | `gen_random_uuid()` |
| `date_repas` | `date` | NON | (UNIQUE) |
| `date_cloture` | `timestamptz` | NON | `now()` |
| `effectif` | `integer` | NON | |
| `auteur` | `text` | NON | |

Contrainte : `effectif >= 0`.

## `parametres`

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `uuid` | NON | `gen_random_uuid()` |
| `cle` | `text` | NON | |
| `portee` | `text` | NON | `'global'` |
| `valeur` | `text` | NON | |
| `date_effet` | `date` | NON | `CURRENT_DATE` |
| `date_fin` | `date` | oui | |

Contrainte : UNIQUE `(cle, portee, date_effet)`.

---

## RLS et Data API

Toutes les tables : RLS activée dès la création (pas après coup). Policy
`cantine_lecture_anon` (`SELECT` pour `anon`) sur les dix tables. Aucune
policy d'écriture pour `anon` — `INSERT`/`UPDATE`/`DELETE` explicitement
révoqués.

Schéma `cantine` exposé dans Data API (Settings → API → Exposed schemas).

Vérifié en conditions réelles le 16/09 via `curl` sur l'API REST (pas
seulement en base) :
- Lecture `anon` sur `cantine.regimes` avec `Accept-Profile: cantine` →
  succès, les 4 lignes renvoyées.
- Écriture `anon` (`POST` avec `Content-Profile: cantine`) → refusée,
  `permission denied for table regimes`.

## Ce qui n'est PAS dans ce document

- Les Edge Functions qui écriront dans ce schéma (aucune encore créée au
  16/09).
- Le filtrage RLS par convive (aujourd'hui, `anon` lit toutes les lignes de
  toutes les tables — pas de policy ligne à ligne). Point ouvert, non
  bloquant à ce volume.

## Requêtes ayant produit ce document

```sql
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'cantine'
order by table_name, ordinal_position;
```

```sql
select tc.table_name, tc.constraint_type, tc.constraint_name, kcu.column_name
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name and kcu.table_schema = tc.table_schema
where tc.table_schema = 'cantine'
order by tc.table_name, tc.constraint_type, tc.constraint_name;
```
