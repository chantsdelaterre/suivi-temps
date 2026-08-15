-- =============================================================================
-- controle_jointure_periodes.sql
-- Date : 2026-08-15
-- But  : contrôle d'intégrité du calendrier de paie.
--        À passer APRÈS toute correction manuelle d'une période.
--
-- Contexte : les boutons d'édition de l'onglet Périodes ont été retirés le
--   15/08/2026 (ils appelaient un back-end GAS disparu et échouaient en
--   silence). Toute correction se fait désormais en SQL — d'où ce contrôle.
--
-- `ecart` = date_debut - date_fin de la précédente, par type :
--     1    → jointif, correct
--     > 1  → TROU (des jours n'appartiennent à aucune période)
--     < 1  → CHEVAUCHEMENT (des jours appartiennent à deux périodes)
--     null → première période du type
--
-- `id_coherent` : le periode_id encode le mois de DATE_FIN
--   (DEC_aaaa_mm / CIV_aaaa_mm). Une correction qui change le mois de fin
--   sans changer l'id le rend menteur — et une génération future
--   recalculant ce mois entrerait en collision, ou sauterait une période.
--
-- ⚠️ Une correction sûre demande TROIS gestes coordonnés :
--    la date_fin, le periode_id si le mois change, et la date_debut de la
--    période suivante. `generer_periodes_suivantes` n'UPDATE jamais : elle
--    ne réparera pas un trou créé à la main.
--
-- Lecture seule. Déploiement : aucun — à copier dans le SQL Editor.
-- =============================================================================

select p.type_periode,
       p.periode_id,
       p.statut,
       p.date_debut,
       p.date_fin,
       lag(p.date_fin) over w                as fin_precedente,
       p.date_debut - lag(p.date_fin) over w as ecart,
       case when p.periode_id like '%' || to_char(p.date_fin, 'YYYY_MM')
            then 'ok' else 'INCOHERENT' end   as id_coherent
from periodes p
window w as (partition by p.type_periode order by p.date_debut)
order by p.type_periode, p.date_debut;
