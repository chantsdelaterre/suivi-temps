# Cantine — note de démarrage

## Contexte

Chants de la Terre, ~40 collaborateurs. Il existe déjà une application **Suivi des temps** :

- Google Apps Script (API JSONP) + Google Sheets (base) + GitHub Pages (frontends statiques)
- Pages : `index.html` (saisie collaborateur), `admin.html`, `manager.html`
- Repo : `github.com/chantsdelaterre/suivi-temps`
- Neuf équipes définies, avec responsables et tokens
- Module de récap paie existant : `Recap_Paie`

La cantine est une **extension** : une page dédiée, accessible depuis un lien sur `index.html`.

Décision de fond déjà actée par ailleurs : migration du développement de Google Apps Script vers Supabase + GitHub. Le choix de stack pour la cantine reste ouvert (voir décisions à trancher).

## Objectif

Permettre à chaque collaborateur de s'inscrire aux repas, et à Hervé (responsable cantine) de connaître les effectifs, d'arbitrer les demandes hors délai et de pointer les repas réellement pris. Puis facturer nominativement.

## Acteurs

- **Collaborateur** : définit sa routine, s'inscrit, se désinscrit, consulte son historique
- **Hervé** : voit les effectifs par jour, valide ou refuse les demandes exceptionnelles, pointe les repas pris
- **Admin** : tarifs, calendrier des jours servis, exports de facturation

## Règles de gestion

1. Inscription au plus tard **la veille à 10h**. Idéal : la semaine précédente pour la semaine à venir.
2. Chaque collaborateur peut définir une **routine hebdomadaire** (ex. tous les jours, ou seulement le vendredi). L'application génère les inscriptions à partir de cette routine.
3. Tout reste modifiable par le collaborateur jusqu'à la deadline.
4. Passé la deadline, une demande n'est **pas refusée** : elle bascule en statut « exceptionnelle, en attente » et Hervé arbitre. Idem pour les désinscriptions tardives.
5. Le contrôle de la deadline est **exclusivement côté serveur**. Jamais dans le JS de la page.

## Modèle de données (proposition)

Trois états distincts à ne surtout pas confondre :

| État | Origine | Rôle |
|---|---|---|
| **Prévu** | généré depuis la routine | confort d'affichage, modifiable librement |
| **Engagé** | figé à la deadline | c'est la commande d'Hervé, et la base de facturation |
| **Pris** | pointé par Hervé au service | contrôle et litiges |

Trois tables :

- `routines` — collaborateur, jour de semaine, actif, date de début / fin de validité
- `inscriptions` — collaborateur, date du repas, statut (prévu / engagé / annulé / exceptionnel en attente / exceptionnel validé / refusé), origine (routine ou manuelle), horodatage, auteur de la dernière modification
- `pointages` — collaborateur, date, présent oui/non, horodatage

Principe : la routine **matérialise** des lignes d'inscription réelles via un déclencheur hebdomadaire (génération de S+1). Elle n'est jamais recalculée à la volée à l'affichage. Sans quoi il devient impossible de reconstituer l'état au moment de la clôture, et la facturation n'est plus défendable.

Facturation assise sur l'**engagé**, pas sur le pris : le repas est cuisiné, l'absent le doit. À valider avec Hervé.

## Décisions à trancher

1. **Mode de règlement.** Deux voies très différentes :
   - *Retenue sur salaire* → remonte dans `Recap_Paie`, pas de facture, relève du régime avantage en nature nourriture.
   - *Facturation nominative réelle* → vente B2C à des particuliers, donc obligations d'e-reporting et de conformité anti-fraude.

   Ce choix conditionne une grande partie du reste. À arbitrer en premier.

2. **Stack.** Rester sur Apps Script (réutilisation immédiate du référentiel collaborateurs, équipes et tokens ; mais Code.gs qui grossit, et tout redéploiement pour un bug cantine touche aussi la paie) ou faire de la cantine le pilote Supabase (module petit et peu critique, bon candidat pour essuyer les plâtres ; mais duplication temporaire de l'identité).

3. **Croisement avec les absences.** Le générateur de routine doit-il exclure les collaborateurs déjà en congés dans Suivi des temps ? Sinon Hervé nettoie à la main toutes les semaines.

4. **Pic de midi.** Si la saisie se concentre au même moment que les pointages d'heures, prévoir la contention (onglet Sheets dédié si on reste sur GAS).

5. **Invités et occasionnels.** Repas pour visiteurs, stagiaires, prestataires : dans le périmètre ou hors périmètre ?

6. **Tarifs.** Un tarif unique ? Historisation des tarifs pour que la facturation d'une période passée reste juste ?

## Points ouverts mineurs

- Jours servis : calendrier configurable (fermetures, jours fériés, saison)
- Historique et export : format attendu pour la facturation
- Notification aux collaborateurs qui n'ont pas de routine (rappel hebdomadaire ?)
