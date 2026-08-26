> ⚠️ **PÉRIMÉ — 26/08/2026.** La conception décrite ici (brouillon en
> base, mode `brouillon:true` dans l'Edge, auto-enregistrement
> silencieux) n'a PAS été retenue. Le besoin réel s'est révélé plus
> simple : de la mémoire, pas du pointage. Livré en localStorage,
> front uniquement. Voir `CLAUDE.md`, section « Saisie collaborateur
> — décisions du 26/08/2026 ».
>
> Le reste du document garde sa valeur : il porte le raisonnement
> métier et les contraintes qui ont mené à cette décision.

# NOTE — Saisie au fil de la journée (brouillon) — conception figée (16/07/2026)

**Besoin métier :** certains collabs veulent saisir leurs heures au fur et à mesure (ex. 06:00, 12:15, 13:30, 15:30), en fermant/rouvrant l'appli entre-temps. Aujourd'hui impossible : un créneau n'est gardé que si début ET fin sont remplis, et chaque enregistrement consomme le quota de 3 modifications/jour.

**Verrou technique :** la règle des 3 modifications (serveur, sauver-saisie). Une saisie au fil de l'eau cramerait le quota en une journée.

**Modèle retenu : brouillon vs saisie validée.**
- Brouillon : le jour s'ouvre en mode brouillon ; le collab tape ses horaires quand il veut (y compris un début seul) ; auto-enregistrement SILENCIEUX côté serveur (temporisé, à la sortie de champ) → survit à la fermeture/réouverture de l'appli. Ne compte PAS de modification, ne touche pas le jour officiel.
- Validation (« Enregistrer » en fin de journée) : le brouillon devient la saisie officielle (calcul du total) → compte pour 1 modification. Le collab garde ses 2 corrections (fenêtre J-5).

**Décisions validées (16/07/2026) :**
1. Brouillon = jour même uniquement. Jours passés (J-1…J-5) = flux d'édition normal.
2. Oubli de valider : brouillon laissé en attente avec rappel visuel ; PAS de validation auto à minuit.
3. UX v1 : saisie libre des horaires. Boutons de pointage « J'arrive / Je pars » possibles plus tard sur le même modèle.
4. Brouillon = 0 modification ; seul « Enregistrer » compte pour 1.

**Persistance serveur obligatoire** (les collabs ferment/rouvrent l'appli dans la journée).

**Esquisse technique (à préciser au build) :**
- Base : stockage du brouillon — colonne dédiée (brouillon jsonb sur jours) OU statut de saisie sur le jour. À trancher au build.
- Edge : sauver-saisie gagne un mode brouillon:true → écrit le brouillon, saute le check 3-modifs + l'incrément. Mode validation = comportement actuel.
- Front (index.html) : ouverture en brouillon (plus de saisie complète imposée), auto-save temporisé, bouton « Enregistrer » = validation, avertissement si créneau incomplet, rappel « brouillon non validé ».

**Statut : conception figée, construction à planifier** (chantier moyen-gros : base + Edge + front, cœur de la saisie collab).
