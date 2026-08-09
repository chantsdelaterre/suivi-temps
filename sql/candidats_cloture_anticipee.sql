-- =============================================================================
-- candidats_cloture_anticipee.sql
-- Date       : 2026-08-09 (lot 2 — clôture partielle de paie par collaborateur)
-- Rôle       : liste les collaborateurs en FIN DE CONTRAT éligibles à une
--              validation anticipée de paie (bornée à leur date de fin), sur une
--              période encore OUVERTE. Exposée au front via l'Edge Function
--              `candidats-cloture` (EXECUTE réservé à service_role).
--
-- DISTINCT ON (hc.collab_id) ... order by date_debut desc, date_fin desc :
--   on ne retient, par collaborateur, que la LIGNE DE CONTRAT LA PLUS RÉCENTE.
--   Ainsi la condition « aucun contrat postérieur » est vraie PAR CONSTRUCTION —
--   inutile d'aller vérifier l'absence d'un contrat suivant par une requête à part.
--
-- date_fin DESC en SECOND critère (à date_debut égale) : en Postgres les NULL
--   passent EN PREMIER sur un tri DESC → un contrat OUVERT (date_fin nulle)
--   l'emporte sur un contrat clos de même date de début. Dans le doute, on ne
--   déclare PERSONNE parti (on ne propose pas la clôture anticipée à tort).
--
-- ⚠️ CREATE FUNCTION re-grante EXECUTE à `public` À CHAQUE création. Les trois
--    revoke/grant en fin de fichier sont donc OBLIGATOIRES après CHAQUE
--    `create or replace` — sinon la fonction redevient exécutable par anon.
--
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- =============================================================================

create or replace function candidats_cloture_anticipee()
returns table (
  collab_id           text,
  nom_affiche         text,
  structure           text,
  date_fin_contrat    date,
  periode_id          text,
  nom_periode         text,
  periode_date_debut  date,
  periode_date_fin    date
)
language sql
stable
as $$
  with dernier_contrat as (
    select distinct on (hc.collab_id)
           hc.collab_id, hc.date_fin, hc.structure, hc.type_periode
    from historique_contrats hc
    order by hc.collab_id, hc.date_debut desc, hc.date_fin desc
  )
  select c.collab_id, c.nom_affiche,
         coalesce(dc.structure, c.structure),
         dc.date_fin, p.periode_id, p.nom_periode,
         p.date_debut, p.date_fin
  from dernier_contrat dc
  join collaborateurs c on c.collab_id = dc.collab_id
  join periodes p
    on p.statut = 'ouverte'
   and p.type_periode = coalesce(dc.type_periode, c.type_periode)
   and dc.date_fin between p.date_debut and p.date_fin
  where dc.date_fin is not null
    and dc.date_fin < current_date
    and not exists (
      select 1 from recap_paie rp
      where rp.periode_id = p.periode_id
        and rp.collab_id  = dc.collab_id
        and rp.date_fin_validation is not null
    )
  order by coalesce(dc.structure, c.structure), c.nom_affiche;
$$;

-- Droits : CREATE FUNCTION re-grante EXECUTE à public → révoquer, puis n'ouvrir
-- qu'à service_role (l'Edge Function candidats-cloture s'exécute en service_role).
revoke execute on function candidats_cloture_anticipee() from public;
revoke execute on function candidats_cloture_anticipee() from anon;
grant  execute on function candidats_cloture_anticipee() to service_role;
