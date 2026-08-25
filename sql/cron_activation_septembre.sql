-- =====================================================================
-- CRON D'ACTIVATION / DÉSACTIVATION AUTOMATIQUE
-- Préparé le 25/08/2026 — À PASSER LE 4 OU 5 SEPTEMBRE 2026
-- =====================================================================
--
-- ⚠️ CONDITION PRÉALABLE ABSOLUE : les contrats doivent être à jour.
--
-- Au 25/08, 23 TESA en cours n'avaient pas de date de fin. Brancher le
-- cron dans cet état RÉACTIVERAIT des personnes parties depuis un mois
-- (Félix BONNET, Martin WOLFF, Michael KOUAKOU, Aubin MILLECAM…, qui
-- n'ont plus saisi depuis fin juillet). Elles recevraient des jours
-- vides chaque matin et fausseraient les compteurs.
--
-- VÉRIFIER AVANT DE PASSER (test à blanc, ne modifie rien) :
--
--   -- Qui serait ACTIVÉ ?
--   select c.collab_id, c.nom_affiche, c.statut
--   from collaborateurs c
--   where coalesce(c.actif, false) = false
--     and exists (select 1 from historique_contrats h
--                 where h.collab_id = c.collab_id
--                   and h.date_debut <= current_date
--                   and (h.date_fin is null or h.date_fin >= current_date))
--   order by c.nom_affiche;
--
--   -- Qui serait DÉSACTIVÉ ?
--   select c.collab_id, c.nom_affiche
--   from collaborateurs c
--   where coalesce(c.actif, false) = true
--     and not exists (select 1 from historique_contrats h
--                     where h.collab_id = c.collab_id
--                       and (h.date_fin is null
--                            or h.date_fin >= current_date - 1
--                            or h.date_debut > current_date))
--   order by c.nom_affiche;
--
-- Les deux listes doivent avoir du sens AVANT de brancher.
--
-- =====================================================================
-- LA RÈGLE
-- =====================================================================
--
-- ACTIVER    : un contrat couvre AUJOURD'HUI.
--              Pas besoin d'anticiper : dans trigger_quotidien,
--              l'activation passe AVANT la génération des jours.
--              Le 15 à 2 h : Jacques devient actif, puis son jour du 15
--              est créé. Un seul passage, pas de jour parasite.
--
-- DÉSACTIVER : aucun contrat en cours, AUCUN CONTRAT À VENIR, et le
--              dernier terminé depuis plus d'un jour.
--
--              ⚠️ « Aucun contrat à venir » est essentiel : un TESA
--              clos le 31/08 avec un contrat au 15/09 déjà enregistré
--              NE DOIT PAS être désactivé entre les deux. Pas de seuil —
--              la pratique ne va jamais au-delà de deux semaines.
--
--              ⚠️ « Terminé depuis plus d'un jour » donne le
--              comportement voulu :
--              - fin de contrat = fin de période → la période est gelée
--                le lendemain, donc la saisie s'arrête de toute façon ;
--              - fin en milieu de période → la personne peut saisir le
--                lendemain, et le cron la désactive la nuit suivante.
--
-- ⚠️ PAS D'EXCLUSION DES ADMINISTRATEURS.
--    L'accès admin passe par la table `admins`, avec son propre token.
--    `collaborateurs.actif` ne le concerne pas : un admin désactivé
--    comme collaborateur GARDE son accès admin. Il perd seulement la
--    génération de ses jours.
--    Règle retenue : les admins ont un contrat à jour.
--    (Et de toute façon `admins.admin_id` ne correspond pas à
--    `collaborateurs.collab_id` — 'admin_pauline' vs 'COLL017'.)
--
-- ⚠️ PLUS DE BASCULE MANUELLE. Le contrat pilote, l'appli suit.
--    Pour désactiver quelqu'un, on raccourcit son contrat (rupture
--    anticipée). Un drapeau manuel réintroduirait la divergence qu'on
--    cherche à supprimer.
--
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. LA FONCTION  (déjà créée en base le 25/08 — ici pour référence)
-- ---------------------------------------------------------------------

create or replace function public.synchroniser_activite()
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_actives integer;
  v_inactives integer;
begin
  -- ACTIVER : un contrat couvre aujourd'hui
  update collaborateurs c
  set actif = true, statut = 'actif'
  where coalesce(c.actif, false) = false
    and exists (
      select 1 from historique_contrats h
      where h.collab_id = c.collab_id
        and h.date_debut <= v_today
        and (h.date_fin is null or h.date_fin >= v_today)
    );
  get diagnostics v_actives = row_count;

  -- DÉSACTIVER : aucun contrat en cours, aucun à venir,
  -- et le dernier terminé depuis plus d'un jour
  update collaborateurs c
  set actif = false, statut = 'inactif'
  where coalesce(c.actif, false) = true
    and not exists (
      select 1 from historique_contrats h
      where h.collab_id = c.collab_id
        and (
          h.date_fin is null
          or h.date_fin >= v_today - 1
          or h.date_debut > v_today
        )
    );
  get diagnostics v_inactives = row_count;

  return v_actives || ' activé(s), ' || v_inactives || ' désactivé(s)';
end;
$function$;

revoke execute on function public.synchroniser_activite() from public;


-- ---------------------------------------------------------------------
-- 2. LE BRANCHEMENT  ⚠️ C'EST CE BLOC QUI ACTIVE TOUT
-- ---------------------------------------------------------------------
-- Seul changement : l'étape 1 appelle synchroniser_activite() au lieu
-- d'activer_collabs_en_attente().
-- Le reste de trigger_quotidien est INCHANGÉ (copie conforme du 25/08).

create or replace function public.trigger_quotidien()
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
  declare
    v_today   date := (now() at time zone 'Europe/Paris')::date;
    v_rapport text := 'Trigger quotidien — ' || to_char(v_today, 'DD/MM/YYYY') || E'\n';
    v_n       integer;
    v_txt     text;
  begin
    -- 1. Synchronisation de l'activité selon les contrats
    begin
      v_txt := public.synchroniser_activite();
      v_rapport := v_rapport || 'Activite          : ' || v_txt || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Activite          : ERREUR - ' || sqlerrm || E'\n';
    end;
    -- 2. Ouverture / gel automatique des périodes
    begin
      v_txt := public.ouvrir_geler_periodes();
      v_rapport := v_rapport || 'Périodes ouv/gel  : ' || v_txt || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Périodes ouv/gel  : ERREUR - ' || sqlerrm || E'\n';
    end;
    -- 3. Génération des périodes suivantes (2 d'avance par type)
    begin
      v_txt := public.generer_periodes_suivantes();
      v_rapport := v_rapport || 'Génération périodes: ' || v_txt || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Génération périodes: ERREUR - ' || sqlerrm || E'\n';
    end;
    -- 4. Génération du jour du jour
    begin
      v_n := public.generer_jour_aujourdhui();
      v_rapport := v_rapport || 'Jours générés     : ' || v_n || ' créé(s)' || E'\n';
    exception when others then
      v_rapport := v_rapport || 'Jours générés     : ERREUR - ' || sqlerrm || E'\n';
    end;
    return v_rapport;
  end;
  $function$;


-- ---------------------------------------------------------------------
-- 3. MARCHE ARRIÈRE
-- ---------------------------------------------------------------------
-- Repasser l'ancienne étape 1 :
--   v_n := public.activer_collabs_en_attente();
--   v_rapport := v_rapport || 'Activation        : ' || v_n || ' collab(s) activé(s)' || E'\n';
-- activer_collabs_en_attente() n'est pas supprimée — elle reste en base,
-- simplement plus appelée.


-- =====================================================================
-- CE QUI VA AVEC, CÔTÉ FRONT (admin-v2.html)
-- =====================================================================
--
-- À faire en même temps, sinon l'écran contredit le cron :
--
-- 1. RETIRER les boutons « Activer » / « Désactiver » du tableau
--    Collaborateurs (~l.1683). Vestiges de la gestion manuelle.
--
-- 2. RETIRER le filtre « En attente » (~l.204). Il ne reste que
--    Tous / Actifs / Inactifs.
--
-- 3. RETIRER l'option « En attente » du select de statut (~l.503) et
--    le défaut à la création (~l.1024).
--    ⚠️ Le remplacer par quoi ? `inactif` — le cron activera la
--    personne le jour où son contrat commence.
--    ⚠️ MAIS `creer_collaborateur_avec_contrat` reçoit un `p_actif` :
--    vérifier que l'admin peut encore poser `actif = true` pour un
--    démarrage le jour même (sinon la personne attend le cron de 2 h).
--
-- 4. Le badge de repli (~l.876-877 et ~l.988) affiche « En attente »
--    pour tout statut ≠ actif/inactif. Devient mort, mais inoffensif.
--
-- ⚠️ NE PAS TOUCHER à la classe CSS `badge-attente` : elle n'a rien à
--    voir avec le statut. Elle sert aux congés payés, aux périodes
--    planifiées et aux contrats sans date de fin.
--
-- ⚠️ Personne n'était en `en_attente` au 25/08 (49 actifs, 12 inactifs).
--
--
-- LE BANDEAU DANS index.html  (textes à écrire)
--
-- Au lieu de couper l'accès brutalement, prévenir :
--   « Votre contrat s'est terminé le 12/09. Dernier jour pour
--     saisir : aujourd'hui. »
--
-- ⚠️ Le push a été écarté : il faudrait que chacun installe la PWA et
--    accepte les notifications. Sur soixante saisonniers, le taux
--    serait insuffisant — et ceux qui ne l'ont pas sont précisément
--    ceux qui oublient de saisir. Le bandeau se voit forcément, puisqu'il
--    faut ouvrir l'appli pour saisir.
--
-- =====================================================================
