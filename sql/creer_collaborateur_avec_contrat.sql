-- =============================================================================
-- creer_collaborateur_avec_contrat.sql
-- Date       : 2026-09-14
-- But        : Création TRANSACTIONNELLE d'un collaborateur + sa 1re ligne
--              d'historique de contrat. Garde-fou : date_fin < date_activation
--              -> exception. Renvoie le collab_id. Appelée par l'Edge
--              creer-collab (qui wrappe cette RPC).
--              17 paramètres (p_taux_horaire et p_date_fin, 16e/17e, ajoutés
--              depuis les 15 d'origine).
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Droits      : postgres + service_role uniquement (verrouillage dans
--              sql/coupure_ecriture_anon.sql).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.creer_collaborateur_avec_contrat(p_collab_id text, p_token text, p_prenom text, p_nom text, p_nom_affiche text, p_email text, p_structure text, p_equipe_id text, p_type_contrat text, p_type_periode text, p_heures_hebdo numeric, p_statut text, p_date_activation date, p_actif boolean, p_matricule_silae text, p_taux_horaire numeric DEFAULT NULL::numeric, p_date_fin date DEFAULT NULL::date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_date_fin is not null and p_date_fin < p_date_activation then
    raise exception 'Date de fin % anterieure au debut % du contrat', p_date_fin, p_date_activation;
  end if;

  insert into collaborateurs (
    collab_id, token, prenom, nom, nom_affiche, email, structure, equipe_id,
    type_contrat, type_periode, heures_hebdo, statut, date_activation, actif, matricule_silae
  ) values (
    p_collab_id, p_token, p_prenom, p_nom, p_nom_affiche, p_email, p_structure, p_equipe_id,
    p_type_contrat, p_type_periode, p_heures_hebdo, p_statut, p_date_activation, p_actif, p_matricule_silae
  );

  insert into historique_contrats (
    collab_id, date_debut, date_fin, structure, type_contrat, type_periode, heures_hebdo, matricule_silae, taux_horaire
  ) values (
    p_collab_id, p_date_activation, p_date_fin, p_structure, p_type_contrat, p_type_periode, p_heures_hebdo, p_matricule_silae, p_taux_horaire
  );

  return p_collab_id;
end;
$function$
;
