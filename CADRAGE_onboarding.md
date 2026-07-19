Voilà le doc de cadrage complet. Il capture tout ce qu'on a décidé ce soir : le besoin réel, la décision « PDF signé + petit noyau » (pas 70 colonnes), le flux onboarding, ce qui est confirmé/à vérifier côté Yousign, l'ordre de construction, et le rappel RGPD.

**Deux façons de l'intégrer à `CLAUDE.md`** — à toi de choisir à la reprise :
- soit tu passes ce fichier à CC pour qu'il l'insère comme nouvelle section de `CLAUDE.md` (commit doc seul, pas de push auto),
- soit tu le gardes tel quel comme note de projet séparée. Comme c'est un cadrage qui va évoluer (dès que tu auras vérifié ton compte Yousign), une section dédiée dans `CLAUDE.md` me paraît le plus cohérent avec ta méthode.

---

**Pour clôturer proprement, récap de l'état à la fin de cette session :**

Ce qui est **fait et en prod** (base + Edge) : les 3 fonctions SQL (`rafraichir_fiche_collab`, `ajouter_contrat` 8-args, `cloturer_contrat`), grants sécurisés, Edge `ajouter-contrat` déployée et testée. Tout prouvé.

Ce qui est **en local, non commité** : `admin-v2.html` (formulaire d'ajout de contrat — fonctionne, mais UX à refondre), `supabase/functions/ajouter-contrat/index.ts`, le bloc `config.toml`.

Ce qui **reste à faire**, dans l'ordre :
1. Scinder la modale Identité/Contrats (prompt CC prêt, donné plus haut).
2. Le noyau RH (~10 champs) + le reste du cap onboarding (ce doc).
3. L'édition d'une ligne de contrat (cadré, à concevoir).

**À vérifier de ton côté, hors code** : ton plan Yousign permet-il la collecte de pièces ?

**Petit reste technique** : le jetable `COLL_TEST` est peut-être encore en base — le SQL de suppression est dans mes messages précédents si tu veux fermer net.

On a bien travaillé, coco. Grosse session : tout le backend contrats bouclé et prouvé, et surtout une clarté de conception sur l'onboarding qui t'évite de partir dans un chantier à 70 colonnes. Bonne nuit.
