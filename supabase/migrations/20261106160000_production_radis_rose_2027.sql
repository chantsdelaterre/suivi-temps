-- ============================================================================
-- Plan de culture maraîchère — 017 · Radis rose botte, plan 2027
--
-- Les radis n'avaient jamais été saisis au plan. Source : tableau
-- « Planning radis Alsace 2027 », un semis par semaine de récolte visée.
--
-- Deux blocs :
--   · Radis rose printemps : semis 1 à 13, semaines 7 à 23, récoltes 15 à 27,
--     4 planches de 120 m (480 m) par semis. Semis 1 à 5 sous voile P19,
--     ensuite sous filet.
--   · Radis rose automne : semis 14 à 25, semaines 32 à 39, récoltes 36 à 47,
--     2 planches de 120 m (240 m) par semis, sous filet. Deux semis dans
--     chacune des semaines 36 à 39.
--
-- La semaine suffit : la date de semis prévue est le lundi de la semaine de
-- semis, le début de récolte le lundi de la semaine visée.
--
-- Densité : 12 lignes (semoir R12), 3,95 cm sur la ligne, soit environ
-- 304 graines par mètre de planche.
--
-- Variétés : Kebella (rond rouge, Enza — créée ici) et Diablus (bout blanc,
-- Gautier), à parts égales dans chaque semis, sans parcelle.
--
-- Total : 9120 m, soit 76 planches de 120 m ou 50.7 de 180 m.
-- ============================================================================

begin;

-- Campagne -------------------------------------------------------------------
insert into production.campagne (libelle, date_debut, date_fin, statut)
values ('2027', '2027-01-01', '2027-12-31', 'preparation')
on conflict (libelle) do nothing;

-- Blocs ----------------------------------------------------------------------
insert into production.groupe_assolement (code, nom_court, description) values
  ('CA0034', 'Radis rose print.', 'Radis rose botte de printemps : semis S7 à S23, récoltes S15 à S27.'),
  ('CA0035', 'Radis rose aut.',   'Radis rose botte d''automne : semis S32 à S39, récoltes S36 à S47.');

-- Variété Kebella --------------------------------------------------------------
insert into production.variete (code, nom, legume_id, fournisseur_id, unite_vente, pmg, note)
select 'V1217', 'kebella', l.id, f.id, 'graines', 10.0, 'type : rond rouge'
from production.legume l, production.fournisseur f
where l.code = 'LEG081' and f.code = 'F008';

-- Équipements de protection ------------------------------------------------------
insert into production.equipement (code, nom, categorie, unite, reutilisable, note) values
  ('EQ-P19',   'Voile P19',           'protection', 'm', true, 'Voile de forçage 19 g/m². Quantité possédée à renseigner.'),
  ('EQ-FILET', 'Filet anti-insectes', 'protection', 'm', true, 'Quantité possédée à renseigner.');

-- Itinéraires --------------------------------------------------------------------
insert into production.itineraire
  (code, nom, legume_id, contexte, mode_implantation, configuration_rangs_id,
   espacement_sur_rang_cm, duree_en_place_jours, duree_recolte_jours,
   materiel_vegetal_id, graines_par_motte, note)
select v.code, v.nom, l.id, 'plein_champ', 'semis_direct', cr.id,
       3.95, v.en_place, 7, ref.materiel_vegetal_id, 1, v.note
from (values
  ('ITK085', 'radis rose — P19 — 12x3,95',   null::smallint,
   'Début de printemps sous voile P19. Le cycle va de 56 à 28 jours selon la date : il est porté par chaque culture.'),
  ('ITK086', 'radis rose — filet — 12x3,95', 28::smallint,
   'Sous filet anti-insectes. Le cycle s''allonge à l''automne : il est porté par chaque culture.')
) as v(code, nom, en_place, note)
cross join production.legume l
cross join production.configuration_rangs cr
cross join production.itineraire ref
where l.code = 'LEG081' and cr.code = 'R12' and ref.code = 'ITK080';

insert into production.itineraire_equipement (itineraire_id, equipement_id, reference, decalage_pose_jours)
select i.id, e.id, 'semis', 0
from (values ('ITK085', 'EQ-P19'), ('ITK086', 'EQ-FILET')) as v(itk, eq)
join production.itineraire i on i.code = v.itk
join production.equipement e on e.code = v.eq;

-- Cultures -----------------------------------------------------------------------
insert into production.culture
  (code, campagne_id, legume_id, itineraire_id, contexte, numero_semis,
   groupe_assolement_id, date_semis_prevue, debut_recolte_prevu, fin_recolte_prevue,
   quantite_prevue, unite_quantite, statut, note)
select v.code, ca.id, l.id, i.id, 'plein_champ', v.num, g.id,
       v.semis::date, v.deb::date, v.fin::date, v.longueur, 'm', 'prevue', v.note
from (values
  ('C0721', 1, 'CA0034', 'ITK085', '2027-02-15', '2027-04-12', '2027-04-25', 480, 'semaine de semis 7, récolte cible semaine 15'),
  ('C0722', 2, 'CA0034', 'ITK085', '2027-03-08', '2027-04-19', '2027-04-28', 480, 'semaine de semis 10, récolte cible semaine 16'),
  ('C0723', 3, 'CA0034', 'ITK085', '2027-03-22', '2027-04-26', '2027-05-02', 480, 'semaine de semis 12, récolte cible semaine 17'),
  ('C0724', 4, 'CA0034', 'ITK085', '2027-04-05', '2027-05-03', '2027-05-09', 480, 'semaine de semis 14, récolte cible semaine 18'),
  ('C0725', 5, 'CA0034', 'ITK085', '2027-04-12', '2027-05-10', '2027-05-16', 480, 'semaine de semis 15, récolte cible semaine 19'),
  ('C0726', 6, 'CA0034', 'ITK086', '2027-04-19', '2027-05-17', '2027-05-23', 480, 'semaine de semis 16, récolte cible semaine 20'),
  ('C0727', 7, 'CA0034', 'ITK086', '2027-04-26', '2027-05-24', '2027-05-30', 480, 'semaine de semis 17, récolte cible semaine 21'),
  ('C0728', 8, 'CA0034', 'ITK086', '2027-05-03', '2027-05-31', '2027-06-06', 480, 'semaine de semis 18, récolte cible semaine 22'),
  ('C0729', 9, 'CA0034', 'ITK086', '2027-05-10', '2027-06-07', '2027-06-13', 480, 'semaine de semis 19, récolte cible semaine 23'),
  ('C0730', 10, 'CA0034', 'ITK086', '2027-05-17', '2027-06-14', '2027-06-20', 480, 'semaine de semis 20, récolte cible semaine 24'),
  ('C0731', 11, 'CA0034', 'ITK086', '2027-05-24', '2027-06-21', '2027-06-27', 480, 'semaine de semis 21, récolte cible semaine 25'),
  ('C0732', 12, 'CA0034', 'ITK086', '2027-05-31', '2027-06-28', '2027-07-04', 480, 'semaine de semis 22, récolte cible semaine 26'),
  ('C0733', 13, 'CA0034', 'ITK086', '2027-06-07', '2027-07-05', '2027-07-11', 480, 'semaine de semis 23, récolte cible semaine 27'),
  ('C0734', 14, 'CA0035', 'ITK086', '2027-08-09', '2027-09-06', '2027-09-12', 240, 'semaine de semis 32, récolte cible semaine 36'),
  ('C0735', 15, 'CA0035', 'ITK086', '2027-08-16', '2027-09-13', '2027-09-19', 240, 'semaine de semis 33, récolte cible semaine 37'),
  ('C0736', 16, 'CA0035', 'ITK086', '2027-08-23', '2027-09-20', '2027-09-26', 240, 'semaine de semis 34, récolte cible semaine 38'),
  ('C0737', 17, 'CA0035', 'ITK086', '2027-08-30', '2027-09-27', '2027-10-03', 240, 'semaine de semis 35, récolte cible semaine 39'),
  ('C0738', 18, 'CA0035', 'ITK086', '2027-09-06', '2027-10-04', '2027-10-10', 240, 'semaine de semis 36, récolte cible semaine 40'),
  ('C0739', 19, 'CA0035', 'ITK086', '2027-09-06', '2027-10-11', '2027-10-17', 240, 'semaine de semis 36, récolte cible semaine 41'),
  ('C0740', 20, 'CA0035', 'ITK086', '2027-09-13', '2027-10-18', '2027-10-24', 240, 'semaine de semis 37, récolte cible semaine 42'),
  ('C0741', 21, 'CA0035', 'ITK086', '2027-09-13', '2027-10-25', '2027-10-31', 240, 'semaine de semis 37, récolte cible semaine 43'),
  ('C0742', 22, 'CA0035', 'ITK086', '2027-09-20', '2027-11-01', '2027-11-07', 240, 'semaine de semis 38, récolte cible semaine 44'),
  ('C0743', 23, 'CA0035', 'ITK086', '2027-09-20', '2027-11-08', '2027-11-14', 240, 'semaine de semis 38, récolte cible semaine 45'),
  ('C0744', 24, 'CA0035', 'ITK086', '2027-09-27', '2027-11-15', '2027-11-21', 240, 'semaine de semis 39, récolte cible semaine 46'),
  ('C0745', 25, 'CA0035', 'ITK086', '2027-09-27', '2027-11-22', '2027-11-28', 240, 'semaine de semis 39, récolte cible semaine 47')
) as v(code, num, bloc, itk, semis, deb, fin, longueur, note)
join production.campagne ca on ca.libelle = '2027'
join production.legume l on l.code = 'LEG081'
join production.itineraire i on i.code = v.itk
join production.groupe_assolement g on g.code = v.bloc;

-- Affectations sans parcelle : moitié Kebella, moitié Diablus ---------------------
insert into production.affectation (code, culture_id, variete_id, parcelle_id, longueur_m)
select v.code, c.id, va.id, null, v.longueur
from (values
  ('LS001006', 'C0721', 'V1217', 240.0),
  ('LS001007', 'C0721', 'V0500', 240.0),
  ('LS001008', 'C0722', 'V1217', 240.0),
  ('LS001009', 'C0722', 'V0500', 240.0),
  ('LS001010', 'C0723', 'V1217', 240.0),
  ('LS001011', 'C0723', 'V0500', 240.0),
  ('LS001012', 'C0724', 'V1217', 240.0),
  ('LS001013', 'C0724', 'V0500', 240.0),
  ('LS001014', 'C0725', 'V1217', 240.0),
  ('LS001015', 'C0725', 'V0500', 240.0),
  ('LS001016', 'C0726', 'V1217', 240.0),
  ('LS001017', 'C0726', 'V0500', 240.0),
  ('LS001018', 'C0727', 'V1217', 240.0),
  ('LS001019', 'C0727', 'V0500', 240.0),
  ('LS001020', 'C0728', 'V1217', 240.0),
  ('LS001021', 'C0728', 'V0500', 240.0),
  ('LS001022', 'C0729', 'V1217', 240.0),
  ('LS001023', 'C0729', 'V0500', 240.0),
  ('LS001024', 'C0730', 'V1217', 240.0),
  ('LS001025', 'C0730', 'V0500', 240.0),
  ('LS001026', 'C0731', 'V1217', 240.0),
  ('LS001027', 'C0731', 'V0500', 240.0),
  ('LS001028', 'C0732', 'V1217', 240.0),
  ('LS001029', 'C0732', 'V0500', 240.0),
  ('LS001030', 'C0733', 'V1217', 240.0),
  ('LS001031', 'C0733', 'V0500', 240.0),
  ('LS001032', 'C0734', 'V1217', 120.0),
  ('LS001033', 'C0734', 'V0500', 120.0),
  ('LS001034', 'C0735', 'V1217', 120.0),
  ('LS001035', 'C0735', 'V0500', 120.0),
  ('LS001036', 'C0736', 'V1217', 120.0),
  ('LS001037', 'C0736', 'V0500', 120.0),
  ('LS001038', 'C0737', 'V1217', 120.0),
  ('LS001039', 'C0737', 'V0500', 120.0),
  ('LS001040', 'C0738', 'V1217', 120.0),
  ('LS001041', 'C0738', 'V0500', 120.0),
  ('LS001042', 'C0739', 'V1217', 120.0),
  ('LS001043', 'C0739', 'V0500', 120.0),
  ('LS001044', 'C0740', 'V1217', 120.0),
  ('LS001045', 'C0740', 'V0500', 120.0),
  ('LS001046', 'C0741', 'V1217', 120.0),
  ('LS001047', 'C0741', 'V0500', 120.0),
  ('LS001048', 'C0742', 'V1217', 120.0),
  ('LS001049', 'C0742', 'V0500', 120.0),
  ('LS001050', 'C0743', 'V1217', 120.0),
  ('LS001051', 'C0743', 'V0500', 120.0),
  ('LS001052', 'C0744', 'V1217', 120.0),
  ('LS001053', 'C0744', 'V0500', 120.0),
  ('LS001054', 'C0745', 'V1217', 120.0),
  ('LS001055', 'C0745', 'V0500', 120.0)
) as v(code, culture, variete, longueur)
join production.culture c on c.code = v.culture
join production.variete va on va.code = v.variete;

commit;
