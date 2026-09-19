-- =============================================================================
-- journal_taches.sql
-- Date       : 2026-09-19
-- But        : Tâches administratives du journal des déclarations, PERSISTÉES.
--              Remplace le mécanisme de borne/clôture. Jusqu'ici
--              journal_mouvements() calculait tout par rapport à
--              max(edite_le) de journal_editions ; avec des tâches persistées
--              la borne perd son rôle — une tâche NON FAITE doit rester
--              visible indéfiniment, pas disparaître à la prochaine clôture.
--              journal_editions n'est PLUS alimentée mais reste lisible pour
--              l'historique déjà constitué (en pratique aucun : le journal
--              n'a jamais servi).
--              Les tâches sont matérialisées à l'OUVERTURE du journal, de
--              façon IDEMPOTENTE (unicité contrat_id+mouvement+regle_id).
--              Date de départ du balayage : 15/09/2026 — rien n'est généré
--              pour les mouvements antérieurs (à porter par la fonction de
--              génération, PAS par cette table).
--              Une tâche est INDÉPENDANTE de sa règle dès sa création :
--              objet, tiers, note et échéance y sont RECOPIÉS. Modifier une
--              règle n'affecte que les tâches futures.
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Droits      : anon/public sans aucun accès ; RLS activé sans policy ; tout
--              pour service_role (l'admin passe par une Edge authentifiée).
-- =============================================================================

-- Décisions ON DELETE (justifiées) :
--   collab_id  → collaborateurs      : RESTRICT — un collaborateur ne se supprime
--                jamais (modèle par inactivation). Protège les pièces
--                justificatives : impossible d'orpheliner des tâches faites.
--   contrat_id → historique_contrats : CASCADE — supprimer un contrat est une
--                correction d'erreur ; ses tâches auto-générées sont parasites
--                et doivent disparaître avec lui.
--   regle_id   → journal_regles      : SET NULL — la tâche est autonome dès sa
--                création (objet/tiers/note/échéance recopiés) ; on ne coupe que
--                la provenance, la tâche survit intacte.
create table public.journal_taches (
  id            bigint generated always as identity primary key,
  collab_id     text    not null,
  contrat_id    bigint  null,
  mouvement     text    null,
  regle_id      bigint  null,
  objet         text    not null,       -- recopié de la règle
  tiers         text    not null,       -- recopié ; mêmes valeurs que journal_regles
  note          text    null,           -- recopiée de la règle
  date_echeance date    null,           -- calculée à la création
  statut        text    not null default 'a_faire',
  fait_le       timestamptz null,
  fait_par      text    null,
  remarque      text    null,           -- saisie par l'admin qui traite ; distincte de note
  cree_le       timestamptz not null default now(),

  -- Idempotence des tâches AUTO : une seule par (contrat, mouvement, règle).
  -- Les tâches MANUELLES ont regle_id null → jamais bloquées (null <> null),
  -- on peut donc en ajouter plusieurs au même contrat. Voulu.
  constraint journal_taches_auto_unique unique (contrat_id, mouvement, regle_id),

  -- Listes fermées (mêmes valeurs que journal_regles).
  constraint journal_taches_mouvement_chk
    check (mouvement is null or mouvement in ('creation','modification','fin','rupture')),
  constraint journal_taches_tiers_chk
    check (tiers in ('MSA','SILAE','GESTIONNAIRE_PAIE','EMPLOYE','FRANCE_TRAVAIL','AUTRE')),
  constraint journal_taches_statut_chk
    check (statut in ('a_faire','faite','sans_objet')),

  -- fait_le et fait_par vont ensemble : les deux, ou aucun.
  constraint journal_taches_fait_paire_chk
    check ( (fait_le is null and fait_par is null)
         or (fait_le is not null and fait_par is not null) ),

  -- Cohérence statut : 'a_faire' n'a ni fait_le ni fait_par ; 'faite' et
  -- 'sans_objet' EXIGENT les deux renseignés.
  constraint journal_taches_statut_coherence_chk
    check ( (statut = 'a_faire' and fait_le is null and fait_par is null)
         or (statut in ('faite','sans_objet') and fait_le is not null and fait_par is not null) ),

  -- Clés étrangères (clauses de suppression justifiées en tête de ce CREATE).
  constraint journal_taches_collab_fk
    foreign key (collab_id) references public.collaborateurs (collab_id) on delete restrict,
  constraint journal_taches_contrat_fk
    foreign key (contrat_id) references public.historique_contrats (id) on delete cascade,
  constraint journal_taches_regle_fk
    foreign key (regle_id) references public.journal_regles (id) on delete set null
);

comment on table public.journal_taches is
  'Tâches administratives persistées du journal des déclarations. Remplace la borne/clôture. Matérialisées idempotemment à l''ouverture du journal (unicité contrat_id+mouvement+regle_id). Indépendantes de leur règle : objet/tiers/note/échéance recopiés à la création.';

-- Index : lister vite les tâches à faire, trier par urgence.
create index journal_taches_statut_idx        on public.journal_taches (statut);
create index journal_taches_date_echeance_idx on public.journal_taches (date_echeance);

-- RLS : ceinture en plus des bretelles du revoke. Aucune policy — service_role
-- contourne RLS par nature (l'Edge fonctionne), et sans policy personne d'autre
-- n'accède à la table.
alter table public.journal_taches enable row level security;

-- Droits (même forme que sql/coupure_ecriture_anon.sql) : rien pour anon/public,
-- tout pour service_role.
revoke all on public.journal_taches from public, anon;
grant  select, insert, update, delete on public.journal_taches to service_role;
