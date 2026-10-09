-- =============================================================================
-- synchroniser_activite.sql
-- Date       : 2026-10-09 · 2026-10-07 · 2026-09-14 (créée) · 2026-09-28 (ajout tâche « envoyer lien »)
-- But        : Synchronise actif/statut des collaborateurs d'après les contrats
--              (historique_contrats). Actif s'il existe un contrat couvrant
--              aujourd'hui ; désactivé sinon (tolérance J-1 sur date_fin,
--              exclusion des contrats à venir). Renvoie « N activé(s), M
--              désactivé(s), P tâche(s) lien, Q tâche(s) règle ». Appelée par
--              trigger_quotidien() (étape 1) ET par les Edge ajouter-contrat /
--              creer-collab (démarrage le jour même, idempotent).
--
-- Ajout du 28/09/2026 — TÂCHE « Envoyer le lien de l'appli » :
--   À chaque TRANSITION inactif->actif (l'UPDATE d'activation ne matche que
--   actif=false), on crée une tâche journal_taches marquée mouvement='activation',
--   tiers='EMPLOYE', statut='a_faire'. Garde-fou d'idempotence : on ne crée PAS si
--   une tâche 'activation' est DÉJÀ à faire pour ce collab (évite les doublons).
--   Prérequis : le CHECK journal_taches_mouvement_chk doit autoriser 'activation'.
--   Réalisé via une CTE modifiante (UPDATE ... RETURNING -> INSERT ... WHERE NOT EXISTS)
--   pour capturer les collabs réellement activés dans la même requête.
--
-- 07/10/2026 : la tâche « Envoyer le lien de l'appli » n'est créée qu'à la toute
--   première activation d'une personne (aucun contrat déjà terminé). Avant, elle se
--   recréait à chaque réactivation (renouvellement tardif, retour), alors que le
--   garde-fou ne regardait que les tâches encore à faire.
--
-- 09/10/2026 : ajout des tâches issues des règles (mouvement 'activation').
--   La condition « toute première entrée » est sortie dans la CTE `premiere`, que
--   les DEUX insertions partagent. Les tâches de règles portent `regle_id` (d'où le
--   `regle_id is null` ajouté au garde-fou de la tâche « lien », qui ne doit compter
--   que les tâches codées en dur). `date_echeance` est calculée depuis le JOUR DE
--   L'ACTIVATION (v_today), selon echeance_jours / echeance_sens de la règle.
--   Filtre de ciblage : règle active, et type_contrat nul (toutes) ou égal à celui
--   de la fiche. Prérequis : le CHECK journal_regles_mouvement_chk doit autoriser
--   'activation' (cf. sql/journal_regles.sql).
--   Garde-fou ins_regles : une seule tâche par (personne, règle), car la contrainte
--   journal_taches_auto_unique ne joue pas quand contrat_id est null.
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Droits      : service_role uniquement. ⚠️ Sans le GRANT ci-dessous, l'appel
--              depuis les Edge échoue en « permission denied » — constaté le
--              14/09/2026.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.synchroniser_activite()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_actives integer;
  v_inactives integer;
  v_taches integer;
  v_taches_regles integer;
begin
  -- ACTIVATION + création des tâches d'entrée (une seule requête) :
  --  1) tâche codée en dur « Envoyer le lien de l'appli »
  --  2) tâches issues des règles journal_regles (mouvement = 'activation')
  -- Les deux seulement à la TOUTE PREMIÈRE activation d'une personne.
  with activ as (
    update collaborateurs c
    set actif = true, statut = 'actif'
    where coalesce(c.actif, false) = false
      and exists (
        select 1 from historique_contrats h
        where h.collab_id = c.collab_id
          and h.date_debut <= v_today
          and (h.date_fin is null or h.date_fin >= v_today)
      )
    returning c.collab_id
  ),
  premiere as (                      -- activations qui sont une toute première entrée
    select a.collab_id
    from activ a
    where not exists (
      select 1 from historique_contrats p
      where p.collab_id = a.collab_id
        and p.date_fin is not null
        and p.date_fin < v_today
    )
  ),
  ins as (
    insert into journal_taches (collab_id, mouvement, objet, tiers, statut)
    select p.collab_id, 'activation', 'Envoyer le lien de l''appli', 'EMPLOYE', 'a_faire'
    from premiere p
    where not exists (               -- pas de doublon avec une tâche « lien » déjà à faire
      select 1 from journal_taches t
      where t.collab_id = p.collab_id
        and t.mouvement = 'activation'
        and t.statut = 'a_faire'
        and t.regle_id is null       -- les tâches issues de règles ne comptent pas
    )
    returning 1
  ),
  ins_regles as (
    insert into journal_taches
      (collab_id, mouvement, regle_id, objet, tiers, note, date_echeance, statut)
    select p.collab_id, 'activation', r.id, r.objet, r.tiers, r.note,
           case when r.echeance_jours is null then null
                when r.echeance_sens = 'avant' then v_today - r.echeance_jours
                else v_today + r.echeance_jours end,
           'a_faire'
    from premiere p
    join collaborateurs c on c.collab_id = p.collab_id
    join journal_regles r
      on r.actif
     and r.mouvement = 'activation'
     and (r.type_contrat is null or r.type_contrat = c.type_contrat)
    where not exists (
      select 1 from journal_taches t
      where t.collab_id = p.collab_id
        and t.mouvement = 'activation'
        and t.regle_id = r.id
    )
    returning 1
  )
  select (select count(*) from activ),
         (select count(*) from ins),
         (select count(*) from ins_regles)
  into v_actives, v_taches, v_taches_regles;

  -- DÉSACTIVATION (inchangé)
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

  return v_actives || ' activé(s), ' || v_inactives || ' désactivé(s), '
      || v_taches || ' tâche(s) lien, ' || v_taches_regles || ' tâche(s) règle';
end;
$function$;

revoke execute on function public.synchroniser_activite() from public, anon, authenticated;
grant execute on function public.synchroniser_activite() to service_role;
