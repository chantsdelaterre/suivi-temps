# MÉMO GIT — suivi-temps

Aide-mémoire personnel. Quatre commandes, toujours dans le même ordre.
**Aucune de ces commandes ne peut détruire ton travail.**

---

## LA SÉQUENCE

Toujours dans le Terminal, dans le dossier `~/suivi-temps`.

### 1. Préparer les fichiers

```
git add admin-v2.html
```

Tu **nommes** les fichiers, un par un, séparés par des espaces :

```
git add supabase/functions/journal-regles/index.ts supabase/config.toml
```

> **Jamais `git add .`** — il attrape tout ce qui traîne, y compris ce que tu
> ne voulais pas envoyer.

### 2. Vérifier

```
git status --short
```

**La commande la plus importante. Elle ne fait rien, elle montre.**

Tu dois voir exactement les fichiers que tu viens de nommer, et rien d'autre.

Comment lire les deux premières colonnes :

| Affichage | Signification |
|---|---|
| `M  fichier` | Modifié, **prêt à partir** (le M est en 1ʳᵉ colonne) |
| `A  fichier` | Nouveau fichier, prêt à partir |
| ` M fichier` | Modifié mais **PAS prêt** (espace devant — tu as oublié le `git add`) |
| ` D fichier` | Supprimé du disque mais pas du dépôt |
| `?? fichier` | Inconnu de git, ignoré |

**La règle : ce qui part, c'est ce qui a une lettre en PREMIÈRE colonne.**

Si quelque chose d'inattendu apparaît, arrête-toi et demande.

### 3. Enregistrer en local

```
git commit -m "Description courte de ce qui change"
```

Rien n'est encore parti sur GitHub. C'est un point de sauvegarde local.

Le message : sans accents ni caractères spéciaux, entre guillemets droits.
Exemples de ton dépôt :

```
git commit -m "Contrats: date de fin obligatoire sauf CDI"
git commit -m "Edge journal-regles: CRUD des regles du journal"
```

### 4. Envoyer sur GitHub

```
git push origin supabase
```

Il demande ton nom d'utilisateur (`chantsdelaterre`) et un mot de passe :
c'est le **token GitHub temporaire** (classic, scope `repo`).

> **Révoque le token immédiatement après le push.**

### 5. Se resynchroniser

```
git fetch
```

À faire après le push. Met à jour ta vue de ce qui est sur GitHub.

---

## CE QUI N'EST PAS DANS LA SÉQUENCE

**Les Edge Functions ne se déploient pas avec `git push`.**
Après avoir poussé une modification dans `supabase/functions/`, il faut :

```
supabase functions deploy <nom-de-la-fonction>
```

Le `WARNING: Docker is not running` est normal et sans conséquence.

**Le SQL ne se déploie pas non plus.** Les fichiers de `sql/` sont des copies
de référence. La base se modifie à la main, dans le SQL Editor de Supabase.

---

## SI ÇA SE PASSE MAL

**Tu as fait `git add` sur un fichier de trop**

```
git restore --staged nom-du-fichier
```

Le retire de la préparation. Ne touche pas au contenu du fichier.

**Tu as supprimé un fichier par erreur** (il apparaît en ` D` au status)

```
git restore nom-du-fichier
```

Le récupère tel qu'il était au dernier commit.

**Tu t'es trompé dans le message du commit, et tu n'as pas encore poussé**

```
git commit --amend -m "Le bon message"
```

Remplace le message du dernier commit.

**Le push est refusé**

En général parce que quelque chose a changé sur GitHub de ton côté. Ne force
rien : fais `git status` et `git fetch`, puis demande.

---

## À NE JAMAIS TAPER SANS COMPRENDRE

Ces commandes détruisent du travail. Elles n'ont aucune raison d'apparaître
dans ta pratique.

| Commande | Ce qu'elle fait |
|---|---|
| `git reset --hard` | Efface tes modifications non committées, définitivement |
| `git push --force` | Écrase l'historique sur GitHub |
| `git clean -fd` | Supprime les fichiers non suivis |
| `git checkout .` | Annule toutes tes modifications locales |

Si quelqu'un (ou une IA) te propose l'une d'elles, demande pourquoi avant.

---

## LE SERVEUR LOCAL

Pour tester avant de pousser, dans `~/suivi-temps` :

```
python3 -m http.server 8080
```

Puis dans le navigateur :

```
http://localhost:8080/admin-v2.html?token=TON_TOKEN
```

`Ctrl+C` dans le Terminal pour arrêter le serveur.

**Toujours tester en local, jamais en prod.**

---

## LA SÉQUENCE COMPLÈTE, EN RÉSUMÉ

```
git add <fichiers>
git status --short          ← vérifier ici
git commit -m "message"
git push origin supabase    ← token, puis le révoquer
git fetch
```

Et si c'est une Edge :

```
supabase functions deploy <nom>
```
