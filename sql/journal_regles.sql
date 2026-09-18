-- =============================================================================
-- journal_regles.sql
-- Date       : 2026-09-18
-- But        : Table des RÈGLES du journal des déclarations. Une règle décrit une
--              TÂCHE administrative déclenchée par un mouvement de contrat
--              (creation / modification / fin / rupture, cf. journal_mouvements()).
--              Le journal reste une vue CALCULÉE : les règles seront JOINTES au
--              mouvement au moment de l'affichage, jamais persistées par mouvement.
--              Ce fichier ne fait QUE la table et ses droits — l'écran
--              d'administration et le branchement dans journal_mouvements()
--              viendront APRÈS (chantiers séparés).
-- Déploiement : MANUEL, copier-coller dans le SQL Editor de Supabase.
--              (ce fichier n'est qu'une copie de référence versionnée du dépôt)
-- Droits      : anon/public sans aucun accès. L'écran d'administration passera
--              par une Edge en service_role, comme le reste de l'appli (même
--              modèle que sql/coupure_ecriture_anon.sql).
-- Note        : listes fermées par CHECK, pas par table de valeurs (courtes et
--              stables). AUCUNE règle de départ : Pauline et Elsa les saisiront
--              elles-mêmes, ce sont elles qui connaissent les démarches.
-- =============================================================================

create table public.journal_regles (
  id             bigint generated always as identity primary key,
  mouvement      text    not null,
  type_contrat   text    null,
  avec_suite     boolean null,
  objet          text    not null,
  tiers          text    not null,
  echeance_jours integer null,
  echeance_sens  text    null,
  note           text    null,
  ordre          integer not null default 0,
  actif          boolean not null default true,
  cree_le        timestamptz not null default now(),
  modifie_le     timestamptz null,
  modifie_par    text    null,

  -- Listes fermées.
  constraint journal_regles_mouvement_chk
    check (mouvement in ('creation','modification','fin','rupture')),
  constraint journal_regles_type_contrat_chk
    check (type_contrat is null or type_contrat in ('TESA','CDI','CDD')),
  constraint journal_regles_tiers_chk
    check (tiers in ('MSA','SILAE','GESTIONNAIRE_PAIE','EMPLOYE','FRANCE_TRAVAIL','AUTRE')),
  constraint journal_regles_echeance_sens_chk
    check (echeance_sens is null or echeance_sens in ('avant','apres')),

  -- echeance_jours et echeance_sens vont ensemble : les deux, ou aucun.
  constraint journal_regles_echeance_paire_chk
    check ( (echeance_jours is null     and echeance_sens is null)
         or (echeance_jours is not null and echeance_sens is not null) ),

  -- Le sens est porté par echeance_sens, pas par le signe.
  constraint journal_regles_echeance_jours_positif_chk
    check (echeance_jours is null or echeance_jours >= 0)
);

comment on table public.journal_regles is
  'Règles du journal des déclarations : une tâche administrative déclenchée par un mouvement de contrat. Jointes au mouvement à l''affichage, jamais persistées par mouvement.';

-- RLS : ceinture en plus des bretelles du revoke. Aucune policy — service_role
-- contourne RLS par nature (l'Edge fonctionne), et sans policy personne d'autre
-- n'accède à la table.
alter table public.journal_regles enable row level security;

-- Droits (même forme que sql/coupure_ecriture_anon.sql) : rien pour anon/public,
-- tout pour service_role (l'admin passera par une Edge authentifiée).
revoke all on public.journal_regles from public, anon;
grant  select, insert, update, delete on public.journal_regles to service_role;
