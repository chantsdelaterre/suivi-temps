# Inventaire des écritures Supabase (front) — préparation migration Edge Function

> ✅ **CHANTIER TERMINÉ (16/07/2026)** — les 8 écritures directes + 2 RPC écrivantes
> sont migrées vers des Edge Functions ; l'écriture `anon` est coupée en base
> (voir `sql/coupure_ecriture_anon.sql` et la section Edge Functions de `CLAUDE.md`).

> Relevé **lecture seule** du 13/07/2026. Objectif : recenser **tous** les points où le
> front écrit en base, avant de faire passer les écritures par une **Edge Function**
> et de **révoquer les droits d'écriture `anon`**.
>
> Périmètre : `index.html`, `admin-v2.html`, `manager.html`.
> Motifs recherchés : `sb.from(...).insert / .update / .delete / .upsert`, `sb.rpc(...)`.

## Groupe 1 — ÉCRITURES DIRECTES sur tables → passeront par l'Edge Function

| Fichier:ligne | Fonction JS | Opération | Table | Ce que ça fait | Déclencheur | ➜ Edge Function |
|---|---|---|---|---|---|---|
| `index.html:1101` | `sauvegarder()` | update | `jours` | Enregistre la saisie collab du jour (type_jour, créneaux c1–c3, commentaire, total, `nb_modifications`+1) | collab | `sauver-saisie` |
| `manager.html:379` | `sauverRemarque()` | update | `jours` | Écrit `remarque_manager` sur un jour | manager | `sauver-remarque` |
| `admin-v2.html:1003` | `upsertRecapPaieCourant()` | upsert | `recap_paie` | Fige les totaux de paie d'un collab/période (validation) | admin | `valider-recap` |
| `admin-v2.html:1113` | `sauverCollab()` (branche ÉDITION) | update | `collaborateurs` | Met à jour les champs admin d'un collab existant | admin | `modifier-collab` |
| `admin-v2.html:1156` | `sauverCollab()` (branche CRÉATION) | update | `collaborateurs` | Écrit le téléphone après création (non géré par la RPC) | admin | `creer-collab` |
| `admin-v2.html:1495` | `importerPaiePeriode(periodeId)` | insert | `paie_detail` | Importe couche 1+2 (photo des `jours`) à l'ouverture de la paie | admin | `importer-paie` |
| `admin-v2.html:1819` | `enregistrerEtValider()` | update | `paie_detail` | Écrit les ajustements admin (`type_jour_valide`, `heures_valide`, `ajuste_admin=true`) | admin | `ajuster-paie` |
| `admin-v2.html:2381` | `cloturerPeriode(periodeId)` | update | `periodes` | Passe le statut `gelee → cloturee` | admin | `cloturer-periode` |

**Sous-total : 8 écritures directes** (index 1, manager 1, admin-v2 6).

## Groupe 2 — RPC qui ÉCRIVENT → déjà serveur, à traiter différemment

| Fichier:ligne | Fonction JS | Opération | RPC | Ce que ça fait | Déclencheur | ➜ Edge Function |
|---|---|---|---|---|---|---|
| `admin-v2.html:955` | `confirmerFinContrat()` | rpc (écrit) | `cloturer_contrat` | Pose `date_fin` sur la ligne de contrat en cours (`historique_contrats`) | admin | `cloturer-contrat` (wrappe la RPC) |
| `admin-v2.html:1135` | `sauverCollab()` (branche CRÉATION) | rpc (écrit) | `creer_collaborateur_avec_contrat` | Crée le collab **et** sa 1re ligne d'historique (transactionnel) | admin | `creer-collab` (wrappe la RPC) |

**Sous-total : 2 RPC écrivantes** (admin-v2 uniquement).

## Groupe 3 — RPC en LECTURE seule → non concernées

| Fichier:ligne | Fonction JS | Opération | RPC | Ce que ça fait | Déclencheur |
|---|---|---|---|---|---|
| `admin-v2.html:569` | `login()` | rpc (lecture) | `verifier_admin` | Vérifie le token admin, renvoie le nom de l'admin (ou null) | admin |

**Sous-total : 1 RPC lecture.**

## Compte total par fichier

| Fichier | Écritures directes | RPC écrivantes | RPC lecture | Client |
|---|---|---|---|---|
| **index.html** | 1 (update) | 0 | 0 | `sb` (l.775) |
| **manager.html** | 1 (update) | 0 | 0 | `sb` (l.173) |
| **admin-v2.html** | 6 (1 insert, 3 update, 1 upsert, +1 update tel.) | 2 | 1 | `sb` (l.502) |
| **TOTAL** | **8** | **2** | **1** | |

## Notes pour la migration

- **Détail admin-v2 des 6 écritures directes** : 1 insert (`paie_detail`), 1 upsert
  (`recap_paie`), 4 update (`collaborateurs`×2, `paie_detail`, `periodes`).
  Décompte brut par verbe : insert 1 / update 4 / upsert 1.
- **Tables écrites en direct** (à couvrir par l'Edge Function + révocation `anon`
  write) : `jours`, `collaborateurs`, `recap_paie`, `paie_detail`, `periodes`.
- **`sauverCollab` contient 3 points d'écriture** (update `collaborateurs` en édition ;
  RPC de création + update téléphone en création) — à garder à l'esprit lors du découpage.
- **Vérifs d'exhaustivité** : un seul client (`sb`, `createClient`) par fichier ; les
  `.from(` totaux (index 16 / admin-v2 35 / manager 4) — le reste sont des lectures
  (`.select`). Aucune écriture via un autre nom de variable ni motif
  `.insert/.update/.delete/.upsert` hors de cette liste.
