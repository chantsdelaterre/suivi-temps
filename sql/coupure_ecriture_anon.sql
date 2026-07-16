-- ============================================================
-- Coupure de l'écriture anon — sécurisation des écritures (2026-07-16)
-- Modèle : le rôle `anon` (clé publishable, publique) est en LECTURE SEULE.
-- Toute écriture passe par les Edge Functions authentifiées, qui écrivent
-- en `service_role`. Ce fichier documente les GRANT/REVOKE appliqués en base.
-- ============================================================

-- B. Compléter les droits service_role (Edge Functions)
grant select, insert, update, delete on paie_detail          to service_role;
grant select, insert, update, delete on recap_paie           to service_role;
grant select, insert, update, delete on historique_contrats  to service_role;

-- C. Révoquer les écritures directes anon sur les tables (SELECT conservé)
revoke insert, update, delete on collaborateurs      from anon;
revoke insert, update, delete on jours               from anon;
revoke insert, update, delete on paie_detail         from anon;
revoke insert, update, delete on periodes            from anon;
revoke insert, update, delete on recap_paie          from anon;
revoke insert, update, delete on historique_contrats from anon;

-- D1. Verrouiller les RPC écrivantes -> service_role uniquement
revoke execute on function public.ajouter_contrat(text,date,text,text,text,numeric,text) from public, anon;
grant  execute on function public.ajouter_contrat(text,date,text,text,text,numeric,text) to service_role;
revoke execute on function public.cloturer_contrat(text,date) from public, anon;
grant  execute on function public.cloturer_contrat(text,date) to service_role;
revoke execute on function public.creer_collaborateur_avec_contrat(text,text,text,text,text,text,text,text,text,text,numeric,text,date,boolean,text) from public, anon;
grant  execute on function public.creer_collaborateur_avec_contrat(text,text,text,text,text,text,text,text,text,text,numeric,text,date,boolean,text) to service_role;

-- D2. Verrouiller les fonctions cron/maintenance (postgres conserve l'EXECUTE en tant que propriétaire)
revoke execute on function public.activer_collabs_en_attente()  from public, anon;
revoke execute on function public.generer_jour_aujourdhui()     from public, anon;
revoke execute on function public.generer_periodes_suivantes()  from public, anon;
revoke execute on function public.ouvrir_geler_periodes()       from public, anon;
revoke execute on function public.rls_auto_enable()             from public, anon;
revoke execute on function public.trigger_quotidien()           from public, anon;

-- Note : verifier_admin(text) reste exécutable par anon (login admin, lecture seule).
