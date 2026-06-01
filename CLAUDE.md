# CLAUDE.md

Règles de travail pour ce projet.

## Git & branches
- **Ne JAMAIS pousser (push) sur la branche `main`.** Travailler uniquement sur la branche `supabase`.
- Toujours tester en local avant de proposer un push.

## Stockage des données (Supabase)
- Les heures sont **toujours stockées en texte `HH:mm`** dans Supabase, **jamais** comme objet `Date`.
- `typeJour` : valeurs autorisées `'travaillée'`, `'CP'`, `'AT'` (attention aux accents — `travaillée` avec deux accents).

## Règles métier
- Limite de **3 modifications par jour par collaborateur**, appliquée côté serveur **ET** frontend.

## Méthode de travail
- **Éditions chirurgicales uniquement** : ne jamais réécrire un fichier entier.
- **Une seule modification à la fois** : on discute, on valide, ensuite on code.
