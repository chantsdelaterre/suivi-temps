# Suivi des temps — Mode d'emploi admin

Ce guide explique comment utiliser l'écran d'administration du Suivi des temps : gérer les collaborateurs et leurs contrats, contrôler les saisies, préparer la paie et faire les déclarations.

**Pour qui :** les personnes qui administrent l'appli au bureau.

**Comment le lire :**

- Pour démarrer, lisez la **Prise en main** (partie 1).
- Pour savoir quoi faire et quand, suivez **Le mois type** (partie 2).
- Pour un geste précis, allez directement à la **fiche « Je dois… »** qui correspond (partie 3).
- En cas de situation inhabituelle, voyez les **Cas particuliers** (partie 4).
- Les mots techniques (TESA, période décalée, RIH…) sont expliqués dans le **Glossaire** (partie 6).

Les captures d'écran utilisent des collaborateurs fictifs.

**Annoter ce guide.** Sous chaque titre, le bouton **💬 Annoter** permet d'ajouter une note. Deux sortes de notes : **Correction** (le guide est faux ou incomplet : elle sera reprise dans le texte, puis marquée traitée) et **Pratique** (une astuce ou un usage du bureau, à partager entre administrateurs). Les notes sont visibles par tous les administrateurs.

**Un problème avec l'appli ?** Contactez le référent de l'appli. Notez ce que vous faisiez, le message affiché, et faites si possible une capture d'écran **sans la barre d'adresse** (voir partie 1).

## 1. Prise en main

### Se connecter

Chaque administrateur a un **code d'accès personnel**. Deux façons d'entrer :

- **Par votre lien personnel** (le plus simple) : il contient votre code et vous connecte directement. Gardez-le dans les favoris de votre navigateur.
- **Par la page admin sans code** : saisissez votre code dans le champ « Token d'accès », puis **Accéder**.

Une fois connecté, votre prénom s'affiche en haut à droite (« Connecté : … »). Si vous voyez « Token invalide », le code est faux ou désactivé : contactez le référent de l'appli.

### La règle de sécurité

**L'adresse de votre page admin, c'est votre clé.** Quiconque la possède a un accès complet : contrats, taux horaires, coordonnées, paie.

- Ne l'envoyez jamais par mail ou message, et ne la notez pas sur papier.
- Sur une capture d'écran destinée à quelqu'un d'autre, **coupez la barre d'adresse**.
- Les impressions (relevés, journal, listes) passent par une fenêtre dédiée qui n'imprime pas l'adresse : utilisez toujours les boutons d'impression de l'appli, jamais l'impression directe du navigateur (Ctrl+P / Cmd+P) sur la page admin.

### Les onglets

| Onglet | À quoi il sert |
| --- | --- |
| 🗂️ **Tâches** | Liste des tâches administratives à faire (envoyer un lien, un bulletin, faire les virements…), créées automatiquement par les mouvements de contrat. Onglet ouvert par défaut. |
| 👥 **Collaborateurs** | La liste des fiches. Créer un collaborateur, ouvrir sa fiche (identité et contrats), lui envoyer son accès, écrire à plusieurs. |
| 🌿 **Équipes** | Les équipes, leur responsable et leurs membres. |
| 📄 **Contrats** | Tous les contrats en un tableau : échéances, renouvellement des TESA en lot, journal des déclarations MSA et Silae. |
| 📅 **Périodes** | Le calendrier des périodes de paie et leur état (planifiée, ouverte, gelée, clôturée). |
| 📊 **Récap** | Les saisies des collaborateurs sur une période, pour les contrôler. |
| 💶 **Paie** | Le contrôle et la validation des relevés d'heures, la clôture de la paie, l'impression des relevés. |
| ⚙️ **Paramètres** | Les règles qui créent les tâches automatiquement. |
| ❓ **Aide** | Ce guide, et les notes des administrateurs. |

### Ce qui se fait tout seul, chaque nuit

Vous n'avez rien à faire pour ces points : l'appli s'en charge pendant la nuit.

- **Activer ou désactiver les comptes** selon les contrats. Un collaborateur est actif dès le premier jour de son contrat. Il reste actif entre deux contrats si le suivant est déjà saisi. Il est désactivé deux jours après la fin de son dernier contrat.
- **Créer le jour de saisie** de chaque collaborateur actif.
- **Ouvrir et geler les périodes de paie** à leurs dates.

Conséquence pratique : **saisissez les contrats à l'avance**. Un contrat saisi avant sa date de début ne demande ensuite aucune action. Un contrat saisi en retard crée des jours manquants (voir partie 4).

## 2. Le mois type

Il y a **deux paies par mois**, sur deux calendriers différents :

| Calendrier | Pour qui | Période | Paie à traiter à partir du |
| --- | --- | --- | --- |
| **Période civile** | les TESA | du 1er au dernier jour du mois | 1er du mois suivant |
| **Période décalée** | CDI, CDD, apprentis | du lundi au premier dimanche à partir du 15 | lundi qui suit (vers le 16-22) |

Exemple pour novembre 2026 : la période décalée va du 19/10 au 15/11 et se traite à partir du 16/11 ; la période civile va du 01/11 au 30/11 et se traite à partir du 01/12.

### Chaque semaine

1. **Onglet Tâches**, filtre « À faire » : traitez les tâches dues (envoyer le lien de l'appli à un nouveau, envoyer un bulletin et une attestation, faire les virements…). Cochez-les puis **✓ Marquer fait**, ou **Ø Sans objet** si elles ne s'appliquent pas.
2. **Onglet Récap** : triez par « Dernière saisie » pour repérer ceux qui ne saisissent plus, et relancez-les.
3. **Saisissez les contrats à l'avance** : embauches, fins de contrat, changements (fiches 3.1 et 3.4).

### En fin de mois, avant le 1er

4. **Renouveler les TESA** du mois suivant : onglet Contrats, « Sans renouvellement », puis **Renouveler la sélection** (fiche 3.2).
5. **Faire les déclarations** : onglet Contrats, bouton **Journal**. Il liste tout ce qui a bougé depuis la dernière édition, rangé par structure puis par destination (MSA pour les TESA, Silae pour les autres). Reportez dans la MSA et Silae, puis clôturez l'édition (fiche 3.5).

### À chaque fin de période (deux fois par mois)

Le lendemain de la fin d'une période, elle passe automatiquement à l'état **gelée** : plus personne ne peut saisir, et elle apparaît dans **Paie → À traiter**.

6. **Choisir la période** dans Paie → À traiter. L'appli récupère les saisies de tous les collaborateurs.
7. **Contrôler et valider chaque relevé** : bouton **📋 Détail** sur chaque ligne. Corrigez si besoin en mode **✏️ Modification** (horaires, type de jour, heures d'arrêt), puis **💾 Enregistrer et valider le relevé** (fiche 3.6).
8. **Clôturer la période** : quand le compteur affiche tous les relevés validés (par exemple « 42 / 42 validés »), cliquez **🔒 Clôturer**. La **Synthèse EVP** donne au passage les absences par plages de dates, à reporter dans Silae ou la MSA (fiche 3.13).
9. **Imprimer les relevés à signer** : Paie → **🔒 Clôturées**, cochez les relevés, **🖨️ Imprimer les relevés sélectionnés**.
10. **Tâches de clôture** : la clôture crée automatiquement les tâches prévues dans Paramètres (aujourd'hui : envoyer bulletin et attestation de travail, 4 jours après). Elles apparaissent dans l'onglet Tâches.

### Quand un collaborateur part en cours de période

Sa paie peut être soldée sans attendre la fin de la période : il apparaît dans Paie → À traiter, bloc **⏱️ Clôtures anticipées** (fiche 3.3).

### À confirmer avec le bureau

- [ ] Quel jour du mois les déclarations sont faites (étape 5).
- [ ] Qui fait quoi entre la validation des relevés, la clôture et les virements.

## 3. Fiches pratiques « Je dois… »

### 3.1 Embaucher quelqu'un et lui envoyer son accès

**Créer la fiche et le contrat**

1. Onglet **Collaborateurs**, bouton **+ Nouveau**.
2. **Identité** : prénom et nom (obligatoires), e-mail, téléphone, matricule Silae, n° de sécurité sociale.
3. **Contrat initial** :
   - **Structure**, **Type de contrat** (CDI, TESA ou CDD) : obligatoires.
   - **Type de période** : se remplit tout seul (civile pour un TESA, décalée pour les autres). Si vous en choisissez une autre, l'appli demande confirmation : c'est possible, mais rare.
   - **Heures / semaine** et **Date de début** : obligatoires.
   - **Date de fin** : obligatoire, sauf pour un CDI.
   - **Taux horaire** et **Équipe** : facultatifs.
4. Contact d'urgence si vous l'avez, puis **Enregistrer**.

Le message « ✓ Collaborateur créé ! » confirme. S'il indique « téléphone non enregistré » ou « n° de sécurité sociale refusé », la fiche est quand même créée : corrigez ces champs en ouvrant la fiche (✏️).

**Quand le compte démarre**

- Date de début aujourd'hui : le collaborateur peut saisir tout de suite.
- Date de début future : rien à faire, le compte s'active tout seul ce jour-là.
- Date de début passée : les jours avant aujourd'hui n'existent pas. Voir partie 4, « Jour manquant ».

**Envoyer l'accès**

À l'activation d'un premier contrat, une tâche **« Envoyer le lien de l'appli »** apparaît dans l'onglet Tâches. Trois façons de l'envoyer :

- **💬 WhatsApp** (sur la tâche ou sur la ligne du collaborateur) : ouvre WhatsApp Web avec le message tout prêt. Il faut être connecté à WhatsApp Web sur ce poste. Le bouton n'apparaît que si le numéro est exploitable.
- **📨** sur la ligne du collaborateur : copie le message d'invitation, à coller où vous voulez.
- **📋 Lien page collab.** dans la fiche : copie le lien seul.

Le message contient le lien, le code d'accès et la façon d'installer l'appli sur le téléphone. Une fois envoyé, cochez la tâche puis **✓ Marquer fait**.

Pas de téléphone ? Le collaborateur peut saisir depuis un ordinateur du bureau avec le même lien.

### 3.2 Renouveler les TESA du mois suivant

Les TESA sont des contrats mensuels : chaque mois, ceux qui continuent ont besoin d'un nouveau contrat. L'appli permet de les renouveler en une fois.

1. Onglet **Contrats**. Il s'ouvre sur « En cours » et « TESA ».
2. Cliquez **Voir** à côté de « 📅 N sans renouvellement » : ce sont les TESA qui se terminent dans 10 jours ou moins, ou depuis moins de 7 jours, sans contrat suivant.
3. **Cochez** ceux qui continuent. Seuls les TESA avec une date de fin et sans contrat suivant ont une case.
4. **Renouveler la sélection**, puis saisissez la **date de début** et la **date de fin** du nouveau contrat, et **Renouveler**.

Le nouveau contrat reprend tout le reste à l'identique : structure, heures, taux, période. Si l'un de ces éléments change pour une personne, renouvelez-la à part depuis sa fiche.

**Si un contrat pose problème, rien n'est créé**, pour aucun des cochés. Le message nomme la personne en cause :

| Message | Que faire |
| --- | --- |
| « … termine le …, après la date de début saisie » | Décochez cette personne, ou corrigez la date de début. |
| « … a déjà un contrat ouvert » | Elle a déjà un contrat sans date de fin : décochez-la. |
| « … n'a pas de date de fin » | Posez d'abord la date de fin depuis sa fiche (crayon ✏️ sur le contrat). |

Astuce : tous les cochés reçoivent les mêmes dates. Si certains reprennent plus tard, faites plusieurs lots.

### 3.3 Solder la paie d'un collaborateur qui part en cours de période

Quand un contrat se termine avant la fin de la période, vous pouvez valider la paie de la personne tout de suite, pour lui remettre son relevé sans attendre.

La personne apparaît dans Paie → À traiter, bloc **⏱️ Clôtures anticipées**, si trois conditions sont réunies :

- sa date de fin est saisie sur son dernier contrat ;
- aucun contrat ne suit ;
- la période de paie est encore ouverte (sinon, sa paie se traite avec celle de tout le monde).

1. Cliquez **Clôturer sa paie**.
2. Une fenêtre propose la date de fin de contrat. Gardez-la, sauf cas particulier. Un avertissement s'affiche si vous choisissez une date au-delà de la fin du contrat.
3. **Confirmer** : l'appli fige ses jours du début de la période jusqu'à cette date, et ouvre son relevé.
4. Contrôlez, corrigez si besoin, puis **💾 Enregistrer et valider le relevé**, comme pour une paie normale (fiche 3.6).
5. Son relevé est alors disponible dans Paie → **🔒 Clôturées**, pour impression.

**Attention :**

- **La date peut être allongée, jamais raccourcie.** Choisissez-la avec soin.
- Une personne qui n'a rien saisi peut quand même être soldée : son relevé indique zéro heure.
- Sa ligne compte comme validée pour la clôture de la période : elle ne bloquera pas le compteur.

### 3.4 Changer un contrat, y mettre fin, rupture anticipée

Tout se fait dans la **fiche du collaborateur** (onglet Collaborateurs, ✏️), zone **Contrats**. L'onglet Contrats ne sert qu'à consulter, sauf pour le renouvellement en lot.

**La question à se poser avant chaque geste : ce qui est enregistré était-il vrai à l'époque ?**

- **Non, c'est une erreur de saisie** (mauvaise date, faute de frappe) : on **corrige la ligne** avec le crayon ✏️.
- **Oui, mais la situation a changé** (passage de 35 h à 28 h, CDD qui devient CDI, changement de structure) : on **ajoute une ligne** avec **+ Nouvel événement**. L'historique reste juste, ce qui compte pour la paie et pour les droits.

**Lire la liste des contrats**

Chaque contrat a une couleur : **gris** = terminé, **bleu** = à venir, **orange** = se termine dans 10 jours sans contrat suivant, **vert** = en cours.

**Les boutons, selon le contrat**

| Bouton | Où il apparaît | Ce qu'il fait |
| --- | --- | --- |
| ✏️ Corriger | contrats en cours et à venir | Corrige une erreur de saisie. Ce qui est modifiable dépend du contrat (voir ci-dessous). |
| 🗑️ Supprimer | contrats à venir seulement | Supprime définitivement un contrat qui n'a pas commencé. Demande confirmation. |
| Renouveler | TESA en cours, sans contrat suivant | Crée le TESA suivant, comme le renouvellement en lot (fiche 3.2). |
| Fin de contrat | CDI, CDD, apprenti en cours, sans date de fin | Pose la date de fin. |
| Modifier la date de fin | CDI, CDD, apprenti en cours, avec date de fin | Change cette date. |
| Rupture anticipée | tout contrat en cours avec une date de fin | Arrête le contrat avant la date prévue (voir plus bas). |
| + Nouvel événement | en bas de la liste | Ajoute un nouveau contrat ou un changement. |

**Ce que le crayon permet de corriger**

| Contrat | À venir | En cours |
| --- | --- | --- |
| **TESA** | tout | date de début, heures, taux, date de fin |
| **CDI, CDD, apprenti** | tout | date de début et taux seulement |

Les heures d'un CDI, CDD ou apprenti en cours sont bloquées : un changement de temps de travail est un **nouvel événement**, pas une correction. Pour un TESA, la date de fin se modifie avec le crayon.

**Mettre fin à un contrat**

- **CDI, CDD, apprenti** : bouton **Fin de contrat**, saisissez la date, puis **Confirmer la fin de contrat**.
- **TESA** : il a déjà une date de fin. Pour l'avancer, corrigez-la avec le crayon.
- Le compte se désactive tout seul deux jours après la fin, s'il n'y a pas de contrat suivant.
- Si la personne part en cours de période, sa paie peut être soldée tout de suite (fiche 3.3).

**Rupture anticipée** (le contrat s'arrête avant la date de fin prévue) :

1. Bouton **Rupture anticipée** sur le contrat en cours. Il n'apparaît que sur un contrat qui a une date de fin.
2. Saisissez la date d'**arrêt réel**, entre le début du contrat et la veille de la fin prévue.
3. **Confirmer la rupture.** La ligne affiche ensuite « rupture anticipée ».

![Rupture anticipée dans la fiche](aide/img/rupture.png)

La date de fin initialement prévue n'est pas conservée : c'est la mention « rupture anticipée » qui garde l'information. Les jours de saisie au-delà de l'arrêt ne sont pas supprimés.

Après chaque geste, pensez au **journal des déclarations** (fiche 3.5) : le changement y apparaît, à reporter dans la MSA ou Silae.

### 3.5 Faire les déclarations MSA et Silae

Le journal liste tout ce qui a bougé dans les contrats depuis la dernière fois, pour le reporter dans la MSA et dans Silae sans rien oublier. **Règle d'or : on modifie d'abord l'appli, ensuite la MSA ou Silae, jamais l'inverse.**

1. Onglet **Contrats**, bouton **Journal**.
2. Le journal en cours s'affiche, rangé par **structure**, puis par **destination** (MSA pour les TESA, Silae pour les autres), puis par **collaborateur**. Chaque mouvement a une case à cocher : « Nouveau TESA du … au … », « Fin de CDD le … », « Rupture anticipée… », « Contrat modifié — vérifier ».
3. Faites les déclarations dans la MSA et Silae. **🖨️ Imprimer** donne une version papier pour cocher au fur et à mesure.
4. Quand tout est reporté : **Clôturer le journal**. Le contenu est archivé tel quel, et le journal repart de zéro.

**À savoir :**

- **Clôturer le journal se fait sans confirmation.** Ne le faites qu'une fois toutes les déclarations faites.
- « Contrat modifié — vérifier » ne dit pas ce qui a changé : l'appli connaît la date de modification, pas le détail. Comparez avec ce qui est déclaré.
- Un collaborateur qui change de structure apparaît dans deux blocs. C'est normal : chaque structure a sa propre déclaration.
- Le matricule Silae n'apparaît que dans les blocs Silae.
- Les **Éditions passées** (les 10 dernières) restent consultables et imprimables, exactement comme elles étaient au moment de la clôture.

### 3.6 Contrôler et valider un relevé d'heures

Une fois la période choisie dans Paie → À traiter, chaque collaborateur a une ligne avec ses totaux : heures travaillées, jours travaillés, CP (en jours), AT et CS (en jours).

1. Cliquez **📋 Détail**. Ses jours s'affichent en **👁 Consultation**.
2. S'il faut corriger, passez en **✏️ Modification**. Vous pouvez changer, jour par jour :
   - le **type de jour** (travaillée, CP, AT, CS) ;
   - les **horaires** d'un jour travaillé : le total se recalcule ;
   - les **heures d'un jour AT ou CS** : 7 h par défaut. Vérifiez-les une par une, et mettez **0** les jours où la personne ne travaille jamais (un temps partiel sans mercredi, par exemple).
   - un **commentaire** sur le jour.
3. Ajoutez si besoin une **note admin** (en haut), visible dans la liste.
4. **💾 Enregistrer et valider le relevé.** La ligne passe à « ✅ Validé » et le compteur « X / Y validés » avance.

**À savoir :**

- **Restez sur le filtre « Tous »** (au-dessus du tableau des jours) quand vous corrigez. L'enregistrement ne prend en compte que les jours affichés.
- Les **CS** (congés spéciaux : naissance, décès, maternité…) ne sont jamais saisis par le collaborateur. C'est vous qui transformez le jour en CS ici.
- Un CP vaut toujours 0 h : il se compte en jours.
- Vos corrections n'effacent pas la saisie d'origine du collaborateur : les deux sont conservées.

### 3.7 Corriger un relevé déjà clôturé

Une erreur découverte après la clôture se corrige collaborateur par collaborateur. La période reste clôturée.

1. Paie → **🔒 Clôturées**. Filtrez par collaborateur ou par période si besoin.
2. **📋 Détail** sur la ligne, puis **✏️ Modification**.
3. Corrigez, puis **💾 Enregistrer et valider le relevé**.
4. Réimprimez le relevé (**📄 PDF**) pour le faire signer à nouveau.

Si la paie est déjà partie dans Silae ou à la MSA, reportez-y la correction vous-même : l'appli ne le fait pas.

### 3.8 Gérer les équipes et leur responsable

L'onglet **Équipes** liste chaque équipe, son responsable et le nombre de membres. **Voir** affiche ses membres.

- **Changer quelqu'un d'équipe** : dans sa fiche, champ **Équipe**, puis **Enregistrer l'identité**.
- **Créer une équipe ou changer de responsable** : pas encore possible depuis l'écran. Demandez au référent de l'appli.
- Le responsable n'a pas besoin d'un lien spécial : il ouvre la page de son équipe avec le bouton **Mon équipe** de son propre espace de saisie.

### 3.9 Écrire à un ou plusieurs collaborateurs

- **À une personne** : cliquez sur son adresse dans la colonne Email de l'onglet Collaborateurs.
- **À plusieurs** :
  1. Filtrez la liste si besoin (structure, type de contrat, recherche).
  2. Cochez les personnes, ou la case en tête de colonne pour toutes les lignes affichées.
  3. **✉️ Écrire (n)** ouvre votre messagerie avec les adresses en **copie cachée** et rh@chantsdelaterre.fr en destinataire.

**À savoir :**

- Changer un filtre ou la recherche **décoche tout**, pour ne jamais écrire à quelqu'un qu'on ne voit pas.
- Les personnes cochées sans adresse sont ignorées, et un message l'indique.
- Avec beaucoup de destinataires, la messagerie ne peut pas tout recevoir d'un coup : l'appli copie alors les adresses. Collez-les dans le champ **Cci** de votre message. Le bouton **Copier les adresses** fait la même chose à la demande.

### 3.10 Suivre les tâches administratives

L'onglet **Tâches** regroupe ce qu'il reste à faire, trié par échéance. La plupart des tâches sont créées automatiquement par les mouvements de contrat et les clôtures de période (fiche 3.11).

- **Filtres** : statut (À faire, Fait, Sans objet), portée (individuelles ou de période), collaborateur, mouvement, type de contrat, tiers, structure.
- **Traiter** : cochez une ou plusieurs tâches, puis **✓ Marquer fait** ou **Ø Sans objet**.
- **Ajouter une tâche à la main** : **+ Ajouter une tâche**. Indiquez l'objet (ce qu'il faut faire) et le tiers concerné (MSA, Silae, gestionnaire de paie, employé, France Travail, autre). Le collaborateur, l'échéance et la remarque sont facultatifs.

### 3.11 Régler les tâches automatiques

Onglet **Paramètres**, section **Règles du journal**. Une règle dit : « quand tel mouvement se produit, créer telle tâche ».

- **Mouvements possibles** : création de contrat, modification, fin de contrat, rupture anticipée, clôture de période, entrée dans l'entreprise (premier contrat).
- Une règle peut viser un type de contrat ou un type de période, et fixer une échéance (par exemple 4 jours après).
- **+ Nouvelle règle** pour en créer une. Une règle peut être désactivée sans être supprimée.

Aujourd'hui, une seule règle est active : à chaque clôture de période, « Envoyer BS et attestation de travail » à l'employé, 4 jours après.

### 3.12 Exporter la liste des collaborateurs

Onglet Collaborateurs, **Exporter en PDF** : la liste telle qu'elle est affichée (mêmes filtres, même tri). Le PDF ne contient ni les liens d'accès ni les matricules.

### 3.13 Sortir la synthèse EVP pour la paie

La synthèse EVP (éléments variables de paie) résume la période pour la saisie dans Silae ou à la MSA : pour chaque collaborateur, les jours travaillés, les heures, et les absences regroupées en plages de dates (« CP du 05/10 au 09/10 (5 j) »).

**Où la trouver :**

- **Paie → À traiter** : bouton **Synthèse EVP** au-dessus du récapitulatif, pour la période choisie. Le filtre de structure (SCEA, SAS, SARL) s'applique.
- **Paie → 🔒 Clôturées** : choisissez d'abord une période dans le filtre « Toutes périodes », puis **Synthèse EVP**.

**Dans la fenêtre :**

- **Tous** : tout le monde. **EVP seuls** : uniquement ceux qui ont une absence (CP, AT, CS).
- Chaque personne apparaît avec son matricule Silae et son n° de sécurité sociale quand ils sont renseignés.
- Les collaborateurs sans aucune heure ni absence sur la période ne sont pas listés : un compteur en bas indique combien.
- **🖨️ Imprimer** donne un tableau compact, une ligne par personne, qui tient sur une page pour une trentaine de collaborateurs.

## 4. Cas particuliers et pièges

**Un collaborateur n'a pas pu corriger sa saisie à temps.** Il peut corriger un jour pendant 5 jours, et 3 enregistrements au maximum. Au-delà, l'écran admin ne permet pas de modifier ses saisies pendant la période (le Récap est en lecture seule). Notez la correction et faites-la au moment de la paie, dans le Détail de son relevé (fiche 3.6).

**Jour manquant : un contrat saisi après sa date de début.** L'appli crée chaque nuit le jour de saisie du jour même, et le jour de la création d'un contrat. Elle ne crée pas les jours passés. Si un contrat démarre le 3 et n'est saisi que le 5, les jours du 3 et du 4 n'existent pas : le collaborateur ne peut pas les saisir. Il n'y a pas encore de bouton pour les rattraper : prévenez le référent de l'appli. D'où la règle : **saisir les contrats à l'avance**.

**« Aucun jour trouvé » chez un collaborateur.** Ce message s'affiche aussi quand son téléphone n'a pas de réseau. Faites-lui d'abord vérifier sa connexion.

**Une personne avec deux fiches.** Quelqu'un qui travaille pour deux structures a une fiche par structure : deux contrats, deux matricules, deux relevés. C'est voulu, la paie est séparée par employeur.

**Un collaborateur entre deux contrats** (par exemple un TESA qui finit le 31 et reprend le 14). Son compte reste actif pendant le trou si le contrat suivant est déjà saisi. Il peut donc saisir des heures pendant cette pause : à surveiller.

**Le compteur « ⚠️ N incohérences » apparaît dans l'onglet Contrats.** Il signale un compte resté actif sans aucun contrat en cours ni à venir. En temps normal il n'apparaît jamais : s'il s'affiche, le traitement de nuit n'a probablement pas tourné. Prévenez le référent de l'appli.

**L'alerte « Moins de 2 périodes planifiées »** en haut de l'écran signifie la même chose : le traitement de nuit ne s'est pas fait. Prévenez le référent de l'appli.

**Une rupture anticipée.** Bouton « Rupture anticipée » sur le contrat, dans la fiche (fiche 3.4). Ne raccourcissez pas simplement la date de fin : la rupture ne serait pas signalée.

**Une erreur découverte après la clôture.** Elle se corrige dans le relevé de la personne, la période reste clôturée (fiche 3.7).

**Un changement de temps de travail en cours d'année.** Ce n'est pas une correction mais un nouvel événement sur la fiche (fiche 3.4) : les heures d'un CDI ou CDD en cours sont d'ailleurs bloquées au crayon.

## 5. Référence des écrans

Une capture par écran, avec des collaborateurs fictifs.

### Tâches

Les tâches sont regroupées par tiers (MSA, gestionnaire de paie, employé…). Chaque carte montre le collaborateur, la tâche et l'échéance. Le téléphone, l'e-mail et le bouton WhatsApp apparaissent quand ils servent.

![Onglet Tâches](aide/img/taches.png)

### Collaborateurs

Une ligne par fiche. Les cases à gauche servent au mail groupé. Colonne Actions : ✏️ ouvre la fiche, 📨 copie le message d'invitation, 💬 l'envoie par WhatsApp.

![Onglet Collaborateurs](aide/img/collabs.png)

### Fiche collaborateur

En haut, le nom, le matricule et le bouton **📋 Lien page collab.** Un clic sur le nom déplie l'identité. En dessous, la liste des contrats et leurs boutons (fiche 3.4).

![Fiche collaborateur](aide/img/fiche.png)

### Contrats

Vue par défaut : contrats en cours, TESA. Les cases servent au renouvellement en lot. Les compteurs en haut à droite signalent les contrats sans renouvellement et, s'il y en a, les incohérences.

![Onglet Contrats](aide/img/contrats.png)

### Journal des déclarations

Ouvert depuis l'onglet Contrats. Rangé par structure, puis par destination (MSA ou Silae), puis par collaborateur.

![Journal des déclarations](aide/img/journal.png)

### Périodes

Le calendrier des périodes et leur état. Tout se fait automatiquement : rien à modifier ici.

![Onglet Périodes](aide/img/periodes.png)

### Récap

Une ligne par collaborateur, avec la date de sa dernière saisie. Triez sur cette colonne pour repérer ceux qui ne saisissent plus. **Voir** affiche ses saisies, en lecture seule.

![Onglet Récap](aide/img/recap.png)

### Paie — À traiter

En haut, les départs à solder (Clôtures anticipées), puis chaque période gelée avec son compteur « X / Y validés » et son bouton **🔒 Clôturer**, actif seulement quand tout est validé. En dessous, le récapitulatif de la période choisie.

![Paie, à traiter](aide/img/paie.png)

### Paie — détail d'un relevé

En mode Modification : type de jour, horaires, heures d'arrêt (ici 3 jours d'AT à 7 h, à vérifier), commentaire. Puis **💾 Enregistrer et valider le relevé**.

![Détail d'un relevé en modification](aide/img/detail.png)

### Paramètres

Les règles qui créent les tâches automatiquement (fiche 3.11).

![Onglet Paramètres](aide/img/parametres.png)

## 6. Glossaire

| Terme | Signification |
| --- | --- |
| **TESA** | Titre emploi simplifié agricole : contrat court, mensuel, déclaré à la MSA. Payé sur la période civile. |
| **Période civile** | Période de paie du 1er au dernier jour du mois. Pour les TESA. |
| **Période décalée** | Période de paie du lundi au premier dimanche à partir du 15. Pour les CDI, CDD et apprentis. |
| **Planifiée / ouverte / gelée / clôturée** | Les 4 états d'une période. Ouverte : on saisit. Gelée (lendemain de la fin) : plus de saisie, la paie est à traiter. Clôturée : paie validée. |
| **Relevé / RIH** | Relevé individuel d'heures : le détail des jours d'un collaborateur sur une période, à signer. |
| **CP** | Congé payé. Compté en jours, vaut 0 h. |
| **AT** | Arrêt de travail (maladie, accident). 7 h par défaut, à vérifier jour par jour. |
| **CS** | Congé spécial (naissance, décès, maternité…). Posé par le bureau uniquement. 7 h par défaut. |
| **EVP** | Éléments variables de paie : heures et absences du mois, à reporter dans Silae ou la MSA. |
| **Clôture anticipée** | Validation de la paie d'un collaborateur qui part, avant la fin de la période. |
| **Journal** | La liste des mouvements de contrats à déclarer à la MSA ou dans Silae. |
| **Nouvel événement** | Un nouveau contrat ou un changement de contrat ajouté sur la fiche. |
| **Actif / inactif** | Actif : le compte fonctionne, le collaborateur reçoit ses jours de saisie. Ne veut pas dire « en poste ». |
