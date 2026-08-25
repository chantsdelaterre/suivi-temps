# SCHEMA_REEL — tables Supabase (suivi-temps)

> **Régénéré le 2026-08-21** à partir d'`information_schema.columns` en base
> (projet `oldkmapumqnibdcniecd`), et non plus des fichiers `sql/` du dépôt.
> Remplace la version du 13/06, qui était fausse sur cinq points (§ « Écarts »).
>
> ⚠️ **Portée de cette vérification.** `information_schema.columns` donne les
> colonnes, types, nullabilité et valeurs par défaut — **rien d'autre**. Les
> clés primaires, clés étrangères, index, contraintes `unique` et `check`, et
> les policies RLS listés ci-dessous proviennent des fichiers `sql/` et **n'ont
> pas été re-vérifiés en base**, à une exception près : les FK vers
> `collaborateurs`, contrôlées le 21/08.

---

## Couverture

Sept tables dans le schéma `public`. Toutes ont désormais leurs colonnes
**confirmées en base** — la distinction « versionnée / déduite » de l'ancien
document n'a plus lieu d'être pour les colonnes.

| Table | `CREATE TABLE` dans `sql/` ? | Colonnes |
|---|---|---|
| `admins` | ❌ non | ✅ confirmées en base |
| `collaborateurs` | ❌ non | ✅ confirmées en base |
| `equipes` | ❌ non | ✅ confirmées en base |
| `historique_contrats` | ✅ oui (partiel) | ✅ confirmées en base |
| `jours` | ❌ non | ✅ confirmées en base |
| `paie_detail` | ✅ oui (partiel) | ✅ confirmées en base |
| `periodes` | ❌ non | ✅ confirmées en base |
| `recap_paie` | ✅ oui (partiel) | ✅ confirmées en base |

⚠️ « partiel » signifie que le fichier `sql/` existe mais **ne reflète plus
l'état réel** : des `ALTER TABLE` ont été passés sans être répercutés dans le
dépôt. Voir « Écarts » en fin de document.

---

## `admins`

Table d'authentification des administrateurs. **Absente de l'ancien document.**
C'est elle que `verifier_admin(p_token)` interroge, et c'est par elle que
passe l'accès admin — indépendamment de tout contrat.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `admin_id` | `text` | NON | |
| `nom` | `text` | oui | |
| `token` | `text` | oui | |
| `actif` | `boolean` | oui | `true` |

⚠️ Trois administrateurs, tokens **sans expiration ni traçabilité**. C'est
l'argument principal du chantier Auth, renforcé depuis que `taux_horaire`
existe : un token admin donne accès aux salaires.

---

## `collaborateurs`

La personne. Ce qui ne change pas quand le contrat change.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `collab_id` | `text` | NON | |
| `prenom` | `text` | NON | |
| `nom` | `text` | NON | |
| `nom_affiche` | `text` | oui | |
| `email` | `text` | oui | |
| `structure` | `text` | oui | |
| `equipe_id` | `text` | oui | |
| `type_contrat` | `text` | oui | |
| `type_periode` | `text` | oui | |
| `heures_hebdo` | `numeric` | oui | |
| `statut` | `text` | oui | `'en_attente'` |
| `date_activation` | `date` | oui | |
| `actif` | `boolean` | oui | `false` |
| `role` | `text` | oui | `'collab'` |
| `employeur` | `text` | oui | |
| `matricule_silae` | `text` | oui | |
| `token` | `text` | oui | |
| `created_at` | `timestamptz` | oui | `now()` |
| `telephone` | `text` | oui | |

`collab_id` est la cible des FK de `historique_contrats`, `jours`,
`paie_detail` et `recap_paie` (vérifié le 21/08).

⚠️ **`structure`, `type_contrat`, `type_periode`, `heures_hebdo` et
`matricule_silae` sont un CACHE**, pas la source de vérité :
`rafraichir_fiche_collab(p_collab_id)` les recopie depuis
`historique_contrats` après chaque écriture de contrat. Un changement fait
directement sur la fiche sera écrasé au prochain rafraîchissement.

⚠️ Seul `statut = 'en_attente'` est traité par le cron d'activation. Poser
`date_activation` sur un collaborateur inactif ne déclenche rien.

---

## `equipes`

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `equipe_id` | `text` | NON | |
| `nom_equipe` | `text` | NON | |
| `nom_manager` | `text` | oui | |
| `manager_token` | `text` | oui | |
| `actif` | `boolean` | oui | `true` |
| `created_at` | `timestamptz` | oui | `now()` |

L'ancien document la donnait pour « schéma inconnu ». `actif` et `created_at`
n'y étaient pas listés.

---

## `historique_contrats`

**Journal en ajout seul — la source de vérité contractuelle.** Une ligne par
contrat, pas par personne. `date_fin` NULL = contrat ouvert.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `bigint` | NON | identity |
| `collab_id` | `text` | NON | FK → `collaborateurs` |
| `date_debut` | `date` | NON | |
| `date_fin` | `date` | oui | NULL = en cours |
| `structure` | `text` | oui | |
| `type_contrat` | `text` | oui | |
| `heures_hebdo` | `numeric` | oui | |
| `matricule_silae` | `text` | oui | |
| `created_at` | `timestamptz` | oui | `now()` |
| `type_periode` | `text` | oui | `'civil'` / `'decalee'` |
| `modifie_le` | `timestamptz` | oui | posé par `modifier_contrat` |
| `modifie_par` | `text` | oui | posé par `modifier_contrat` |
| `taux_horaire` | `numeric` | oui | **ajoutée le 21/08** |
| `rupture_anticipee` | `boolean` | **NON** | `false` — **ajoutée le 21/08** |

Index (non re-vérifié) : `idx_historique_contrats_collab_date (collab_id, date_debut)`.
RLS (non re-vérifiée) : activée ; policy SELECT `anon`.

⚠️ **`taux_horaire` n'est PAS une entrée de calcul.** L'appli ne calcule
aucune rémunération — le taux est une information à recopier vers la MSA,
comme les heures.

⚠️ **Ne jamais écraser `date_fin` pour prolonger un contrat.** Un
renouvellement ouvre une nouvelle ligne. Écraser détruit l'information (le
droit, la paie rétroactive, l'ancienneté TESA).

⚠️ `rupture_anticipee` marque une fin écourtée. La date initialement prévue
n'est pas conservée — décision assumée, le drapeau porte l'information.

---

## `jours`

Saisie quotidienne. Généré par `generer_jour_aujourdhui()` (idempotente via
`ON CONFLICT DO NOTHING`).

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `jour_id` | `text` | NON | format `collab_id_YYYY-MM-DD` |
| `collab_id` | `text` | oui | |
| `date_jour` | `date` | oui | |
| `jour_semaine` | `text` | oui | |
| `periode_id` | `text` | oui | |
| `type_jour` | `text` | oui | |
| `c1_debut` · `c1_fin` | `text` | oui | créneau 1 |
| `c2_debut` · `c2_fin` | `text` | oui | créneau 2 |
| `c3_debut` · `c3_fin` | `text` | oui | créneau 3 |
| `commentaire` | `text` | oui | |
| `total_heures` | `numeric` | oui | `0` |
| `total_hebdo_prog` | `numeric` | oui | `0` |
| `nb_modifications` | `integer` | oui | `0` |
| `date_derniere_modif` | `text` | oui | |
| `remarque_manager` | `text` | oui | |
| `created_at` | `timestamptz` | oui | `now()` |

⚠️ Un collaborateur créé après le cron quotidien (~00:10) n'obtient pas de
jour automatiquement : relancer `generer_jour_aujourdhui()` après `actif = true`.

---

## `paie_detail`

Photo figée jour par jour. **Deux couches** : couche 1 = saisie collaborateur
recopiée fidèlement, couche 2 = corrections admin.

| Colonne | Type | Null | Défaut | Couche |
|---|---|---|---|---|
| `id` | `bigint` | NON | identity | |
| `periode_id` | `text` | NON | | |
| `collab_id` | `text` | NON | FK | |
| `date_jour` | `date` | NON | | |
| `jour_semaine` | `text` | oui | | |
| `date_cloture` | `timestamptz` | oui | `now()` | |
| `type_jour` | `text` | oui | | 1 |
| `c1_debut` · `c1_fin` | `text` | oui | | 1 |
| `c2_debut` · `c2_fin` | `text` | oui | | 1 |
| `c3_debut` · `c3_fin` | `text` | oui | | 1 |
| `total_heures` | `numeric` | oui | | 1 |
| `commentaire` | `text` | oui | | 1 |
| `remarque_manager` | `text` | oui | | 1 |
| `total_hebdo_prog` | `numeric` | oui | | 1 |
| `nb_modifications` | `integer` | oui | | 1 |
| `date_derniere_modif` | `text` | oui | | 1 |
| `type_jour_valide` | `text` | oui | | 2 |
| `heures_valide` | `numeric` | oui | heures retenues paie | 2 |
| `ajuste_admin` | `boolean` | oui | `false` | 2 |
| `note_admin` | `text` | oui | | 2 |
| `date_ajuste_admin` | `timestamptz` | oui | horodatage `ajuster-paie` | 2 |
| `c1_debut_valide` · `c1_fin_valide` | `text` | oui | | **2** |
| `c2_debut_valide` · `c2_fin_valide` | `text` | oui | | **2** |
| `c3_debut_valide` · `c3_fin_valide` | `text` | oui | | **2** |

⚠️ **Les six colonnes `*_valide` de créneaux étaient absentes de l'ancien
document.** La couche 2 stocke donc les créneaux corrigés, pas seulement le
total d'heures.

Contraintes (non re-vérifiées) : FK `collab_id` ; **unique
`(periode_id, collab_id, date_jour)`**.
Index (non re-vérifié) : `idx_paie_detail_periode_collab (periode_id, collab_id)`.
RLS (non re-vérifiée) : activée ; policies SELECT / INSERT / UPDATE `anon`.

⚠️ **L'import est append-only** : une ligne importée n'est jamais rafraîchie
depuis `jours`. Supprimer un jour source ne retire pas la ligne de paie — ça
crée un orphelin.

---

## `periodes`

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `periode_id` | `text` | NON | format `CIV_aaaa_mm` / `DEC_aaaa_mm` |
| `nom_periode` | `text` | oui | |
| `type_periode` | `text` | oui | `'civil'` / `'decalee'` |
| `date_debut` | `date` | oui | |
| `date_fin` | `date` | oui | |
| `date_cloture` | `date` | oui | |
| `statut` | `text` | oui | `'planifiee'` |
| `created_at` | `timestamptz` | oui | `now()` |

`statut` : `planifiee` · `ouverte` · `gelee` · `cloturee`.

⚠️ **`date_cloture` existe bel et bien** — l'ancien document la déclarait
« ABANDONNÉE ». Reste à vérifier si elle est effectivement renseignée.

⚠️ Une période gelée reste écrivable via `ajuster-paie` et `valider-recap` :
le statut n'est pas contrôlé. Noté au backlog.

---

## `recap_paie`

Synthèse agrégée figée. Une ligne par collaborateur et par période.

| Colonne | Type | Null | Défaut |
|---|---|---|---|
| `id` | `bigint` | NON | identity |
| `periode_id` | `text` | NON | |
| `collab_id` | `text` | NON | FK |
| `nom_affiche` | `text` | oui | |
| `heures_travaillees` | `numeric` | oui | total |
| `heures_at` | `numeric` | oui | total en heures |
| `heures_cs` | `numeric` | oui | total en heures |
| `nb_cp` | `integer` | oui | nombre de jours CP |
| `nb_jours_travailles` | `integer` | oui | |
| `statut_validation` | `text` | oui | |
| `date_validation` | `text` | oui | |
| `statut_signature` | `text` | oui | |
| `note_admin` | `text` | oui | |
| `created_at` | `timestamptz` | oui | `now()` |
| `nb_at` | `integer` | oui | `0` — **`ALTER` non tracké** |
| `nb_cs` | `integer` | oui | `0` — **`ALTER` non tracké** |
| `date_fin_validation` | `date` | oui | clôture partielle (lot 2, août) |

⚠️ **`nb_at` et `nb_cs` EXISTENT.** L'ancien document affirmait le contraire
(« stocke `heures_at`/`heures_cs` mais pas `nb_at`/`nb_cs` »). Elles ont été
ajoutées par un `ALTER` jamais répercuté dans `sql/recap_paie.sql`.

Contraintes (non re-vérifiées) : FK `collab_id` ; **unique
`(periode_id, collab_id)`** → upsert possible.
RLS (non re-vérifiée) : activée ; policies SELECT / INSERT / UPDATE `anon`.
⚠️ À resécuriser — ouvertes en phase DEV le 13/06.

---

## Écarts constatés le 21/08 avec la version du 13/06

Le document précédent était faux sur cinq points, ce qui justifie de l'avoir
régénéré depuis la base plutôt que corrigé :

1. **`admins` n'y figurait pas du tout.**
2. **`paie_detail`** : six colonnes `*_valide` de créneaux manquantes.
3. **`recap_paie`** : `nb_at`, `nb_cs` et `date_fin_validation` manquantes —
   et une note affirmant explicitement que les deux premières n'existaient pas.
4. **`periodes.date_cloture`** déclarée « ABANDONNÉE » alors qu'elle existe.
5. **`historique_contrats`** : `modifie_le` et `modifie_par` manquantes (plus
   `taux_horaire` et `rupture_anticipee`, ajoutées ce jour).

**Cause commune** : des `ALTER TABLE` passés directement au SQL Editor sans
être répercutés dans `sql/`. Le dépôt ne peut pas servir de source de vérité
sur le schéma — seule la base le peut.

---

## Ce qui n'est PAS dans ce document

- **Les fonctions et RPC** ne sont pas versionnées dans le dépôt (`sql/` n'en
  contient que quelques-unes). `contrats_liste`, `candidats_cloture_anticipee`,
  `derniere_saisie_par_collab`, `compteurs_paie_periodes` n'existent qu'en base.
  **Porté au backlog.**
- **Clés, index, contraintes et RLS** : repris de `sql/`, non re-vérifiés.
  Pour les obtenir réellement :

```sql
select tc.table_name, tc.constraint_type, tc.constraint_name,
       kcu.column_name
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
where tc.table_schema = 'public'
order by tc.table_name, tc.constraint_type;
```

## Requête ayant produit ce document

```sql
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;
```

⚠️ Sa sortie dépasse la fenêtre d'affichage de Supabase et se coupe avant
`recap_paie` — relancer table par table pour les dernières.
