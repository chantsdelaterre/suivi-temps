-- Onglet « Aide » de admin-v2.html : notes des administrateurs sur le guide.
-- Accès uniquement par l'Edge aide-annotations (service_role).
create table public.aide_annotations (
  id          bigint generated always as identity primary key,
  section     text not null check (length(section) between 1 and 200),
  nature      text not null check (nature in ('correction','pratique')),
  texte       text not null check (length(texte) between 1 and 2000),
  auteur      text not null,
  cree_le     timestamptz not null default now(),
  traitee     boolean not null default false,
  traitee_par text,
  traitee_le  timestamptz,
  retiree     boolean not null default false
);

alter table public.aide_annotations enable row level security;
revoke all on table public.aide_annotations from public, anon, authenticated;
grant select, insert, update on table public.aide_annotations to service_role;
