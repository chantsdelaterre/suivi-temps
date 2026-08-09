# SCHEMA_REEL — tables Supabase (suivi-temps)

> Généré le 2026-06-12 (**mis à jour le 2026-06-13**), à partir des fichiers `sql/` réels du dépôt (pas de
> mémoire). Quand une table n'a **pas** de `CREATE TABLE` versionné, c'est
> **signalé** et les colonnes ne sont que **déduites** des fonctions/inserts
> `sql/` (donc partielles, types souvent inconnus). À confirmer en base via
> `information_schema.columns` si besoin de la vérité absolue.

## Couverture

| Table | `CREATE TABLE` dans `sql/` ? | Fichier source |
|---|---|---|
| `historique_contrats` | ✅ oui | `sql/historique_contrats.sql` |
| `paie_detail` | ✅ oui | `sql/paie_detail.sql` |
| `recap_paie` | ✅ oui | `sql/recap_paie.sql` |
| `jours` | ❌ non | déduit de `sql/generer_jour_aujourdhui.sql` |
| `periodes` | ❌ non | déduit de `sql/generer_periodes_suivantes.sql` |
| `collaborateurs` | ❌ non | déduit de `sql/activer_collabs_en_attente.sql`, `generer_jour_aujourdhui.sql` + FK |
| `equipes` | ❌ non | **aucune référence dans `sql/`** |

---

# A. Tables avec schéma versionné (fiable)

## `historique_contrats` — `sql/historique_contrats.sql`
Évolution du contexte contractuel (1 ligne par changement ; `date_fin` NULL = en cours).

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `bigint` (identity) | PK |
| `collab_id` | `text` | NOT NULL, FK → `collaborateurs.collab_id` |
| `date_debut` | `date` | NOT NULL |
| `date_fin` | `date` | NULL = contrat en cours |
| `structure` | `text` | |
| `type_contrat` | `text` | |
| `heures_hebdo` | `numeric` | |
| `matricule_silae` | `text` | |
| `created_at` | `timestamptz` | `default now()` |
| `type_periode` | `text` | `check in ('civil','decalee')` |

Index : `idx_historique_contrats_collab_date (collab_id, date_debut)`.
RLS : activée ; policy **SELECT** `anon` (lecture ouverte phase DEV). ✅ **Résolu le 16/07/2026** : écriture anon RÉVOQUÉE, `service_role` dispose des droits, écritures via Edge Functions (voir `sql/coupure_ecriture_anon.sql`).

## `paie_detail` — `sql/paie_detail.sql`
Photo figée jour par jour (niveau 2). Couche 1 = copie des `jours` ; couche 2 = validation admin.

| Colonne | Type | Contraintes / rôle |
|---|---|---|
| `id` | `bigint` (identity) | PK |
| `periode_id` | `text` | NOT NULL (pas de FK) |
| `collab_id` | `text` | NOT NULL, FK → `collaborateurs.collab_id` |
| `date_jour` | `date` | NOT NULL |
| `jour_semaine` | `text` | |
| `date_cloture` | `timestamptz` | `default now()` |
| `type_jour` | `text` | couche 1 |
| `c1_debut` | `text` | couche 1 |
| `c1_fin` | `text` | couche 1 |
| `c2_debut` | `text` | couche 1 |
| `c2_fin` | `text` | couche 1 |
| `c3_debut` | `text` | couche 1 |
| `c3_fin` | `text` | couche 1 |
| `total_heures` | `numeric` | couche 1 |
| `commentaire` | `text` | couche 1 |
| `remarque_manager` | `text` | couche 1 |
| `total_hebdo_prog` | `numeric` | couche 1 |
| `nb_modifications` | `integer` | couche 1 |
| `date_derniere_modif` | `text` | couche 1 |
| `type_jour_valide` | `text` | couche 2 (peut devenir CS) |
| `heures_valide` | `numeric` | couche 2 (heures retenues paie) |
| `ajuste_admin` | `boolean` | `default false` (jour modifié admin ?) |
| `note_admin` | `text` | couche 2 |
| `date_ajuste_admin` | `timestamptz` | couche 2 — ajoutée le 13/06 (ALTER), nullable. **Écrite par l'Edge `ajuster-paie` depuis le 09/08/2026** (jamais par le front — valeur posée côté serveur). Ajustements **antérieurs = NULL, non reconstituables** → « Modif admin » sans date à l'écran Détail de paie (~113 lignes) |

Contraintes : FK `collab_id` ; **unique `(periode_id, collab_id, date_jour)`**.
Index : `idx_paie_detail_periode_collab (periode_id, collab_id)`.
RLS : activée ; policies **SELECT / INSERT / UPDATE** `anon` (lecture+écriture ouvertes phase DEV). ✅ **Résolu le 16/07/2026** : écriture anon RÉVOQUÉE, `service_role` dispose des droits, écritures via Edge Functions (voir `sql/coupure_ecriture_anon.sql`).

## `recap_paie` — `sql/recap_paie.sql`
Synthèse agrégée figée (niveau 3). 1 ligne par collab/période.

| Colonne | Type | Contraintes / rôle |
|---|---|---|
| `id` | `bigint` (identity) | PK |
| `periode_id` | `text` | NOT NULL |
| `collab_id` | `text` | NOT NULL, FK → `collaborateurs.collab_id` |
| `nom_affiche` | `text` | |
| `heures_travaillees` | `numeric` | total |
| `heures_at` | `numeric` | total (heures) |
| `heures_cs` | `numeric` | total (heures) |
| `nb_at` | `integer` | `default 0` — nombre de jours AT |
| `nb_cs` | `integer` | `default 0` — nombre de jours CS |
| `nb_cp` | `integer` | nombre de jours CP |
| `nb_jours_travailles` | `integer` | |
| `statut_validation` | `text` | workflow |
| `date_validation` | `text` | workflow |
| `date_fin_validation` | `date` | **lot 2** — borne de clôture partielle (NULL = validation normale ; date = validé jusqu'à cette date incluse) |
| `statut_signature` | `text` | workflow |
| `note_admin` | `text` | workflow |
| `created_at` | `timestamptz` | `default now()` |

Contraintes : FK `collab_id` ; **unique `(periode_id, collab_id)`** (→ upsert possible).
RLS : activée ; policies **SELECT / INSERT / UPDATE** `anon` (lecture+écriture ouvertes phase DEV, **ouvertes le 13/06** — `grant` + 3 policies). Consigné dans `sql/recap_paie.sql`. ⚠️ À resécuriser post-15. ✅ **Résolu le 16/07/2026** : écriture anon RÉVOQUÉE, `service_role` dispose des droits, écritures via Edge Functions (voir `sql/coupure_ecriture_anon.sql`).
Note : stocke `heures_at`/`heures_cs` (heures) **et** `nb_at`/`nb_cs` (nombre de jours AT/CS, `default 0`) et `nb_cp` (jours). `date_fin_validation` (lot 2) borne la validation à une date pour la clôture partielle anticipée d'un collaborateur.
⚠️ **Corrigé le 2026-08-09 (vérifié en base)** : la note précédente affirmait à tort l'**absence** de `nb_at`/`nb_cs` (« mais pas nb_at/nb_cs ») — ces colonnes existent bel et bien en base. Ce n'était donc pas un simple oubli mais une affirmation CONTRAIRE à la base, désormais rectifiée.

---

# B. Tables SANS schéma versionné (⚠️ colonnes seulement déduites)

> Aucune de ces tables n'a de `CREATE TABLE` dans `sql/`. Les colonnes ci-dessous
> proviennent **uniquement** des inserts/références des fonctions `sql/` — elles
> sont donc **partielles** et **les types ne sont pas garantis**. D'autres
> colonnes existent côté app (front) sans être prouvées par `sql/` : non listées
> ici pour ne pas inventer. **Vérifier en base pour la liste exacte.**

## `jours` — ❌ pas de CREATE TABLE
Colonnes **confirmées par `sql/generer_jour_aujourdhui.sql`** (insert) :
`jour_id` (clé, format `collab_id_YYYY-MM-DD`), `collab_id`, `date_jour` (`date`),
`jour_semaine` (`text`), `periode_id`, `type_jour` (défaut `'travaillée'`).
→ D'autres colonnes existent (créneaux `c1_debut`…`c3_fin`, `total_heures`,
`commentaire`, `total_hebdo_prog`, `nb_modifications`, `date_derniere_modif`,
`remarque_manager`, `created_at`) mais **hors `sql/`** — à confirmer en base.

## `periodes` — ❌ pas de CREATE TABLE
Colonnes **confirmées par `sql/generer_periodes_suivantes.sql`** (insert) :
`periode_id` (format `CIV_aaaa_mm` / `DEC_aaaa_mm`), `nom_periode`, `type_periode`
(`'civil'` / `'decalee'`), `date_debut` (`date`), `date_fin` (`date`), `statut`
(`'planifiee'` / `'ouverte'` / `'gelee'` / `'cloturee'`).
→ `date_cloture` : **ABANDONNÉE** (mentionnée comme non renseignée dans le SQL).

## `collaborateurs` — ❌ pas de CREATE TABLE
Colonnes **confirmées par les fonctions `sql/`** (`activer_collabs_en_attente.sql`,
`generer_jour_aujourdhui.sql`) + FK : `collab_id` (PK, cible des FK des 3 tables
versionnées), `statut`, `actif` (`boolean`), `date_activation`, `type_periode`.
→ D'autres colonnes existent côté app (`nom_affiche`, `prenom`, `nom`, `token`,
`email`, `equipe_id`, `role`, `employeur`, `structure`, `type_contrat`,
`heures_hebdo`, `matricule_silae`) mais **hors `sql/`** — à confirmer en base.

## `equipes` — ❌ pas de CREATE TABLE, aucune référence dans `sql/`
**Schéma inconnu côté `sql/`.** Colonnes vues côté app (non prouvées) :
`equipe_id`, `nom_equipe`, `nom_manager`, `manager_token`. **À confirmer en base.**

---

## Requête pour obtenir la vérité absolue (toutes tables)
```sql
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;
```
