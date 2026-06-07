-- =============================================================================
-- seed_historique_contrats.sql
-- Date       : 2026-06-07
-- But        : PEUPLEMENT INITIAL de historique_contrats — une première ligne
--              par collaborateur, copiée depuis `collaborateurs`
--              (collab_id, structure, type_contrat, heures_hebdo,
--              matricule_silae).
--              date_debut = 2026-01-01 (date CONVENTIONNELLE d'amorçage),
--              date_fin = NULL (contrat en cours).
--              Couvre TOUS les collaborateurs (actifs ET inactifs).
-- Idempotent : garde-fou `WHERE NOT EXISTS` — n'insère la ligne initiale que
--              si le collab n'a encore AUCUNE ligne d'historique. Relançable
--              sans créer de doublon (ne « complète » pas un historique déjà
--              commencé : c'est un seed, pas une réparation).
-- Exclusion  : `TEST001` est exclu (collaborateur de test).
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              Conseil : tester en `begin; ... rollback;` avant exécution réelle.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

insert into public.historique_contrats
  (collab_id, date_debut, date_fin, structure, type_contrat, heures_hebdo, matricule_silae)
select
  c.collab_id,
  date '2026-01-01' as date_debut,   -- date conventionnelle d'amorçage
  null::date        as date_fin,     -- contrat en cours
  c.structure,
  c.type_contrat,
  c.heures_hebdo,
  c.matricule_silae
from public.collaborateurs c
where c.collab_id <> 'TEST001'        -- exclusion du collaborateur de test
  and not exists (                    -- garde-fou anti-doublon (idempotence)
    select 1
    from public.historique_contrats h
    where h.collab_id = c.collab_id
  );
