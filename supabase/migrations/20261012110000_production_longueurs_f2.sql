-- ============================================================================
-- Plan de culture maraîchère — 016 · Longueurs réelles des planches de F2
--
-- F2 (parcelle P0023) est la seule parcelle qui ne soit pas un
-- parallélogramme. L'import avait supposé 140 m partout, faute de mieux ;
-- ses 91 planches vont en réalité de 104 m au nord à 163 m au sud, par pas
-- de 0,66 m.
--
-- Conséquence : la surface utile de F2 passe de 216,58 à 206,60 ares.
-- L'écart de 9,98 ares était déjà faux dans FileMaker, qui retenait lui
-- aussi une longueur unique pour toute la parcelle.
--
-- La planche numéro 1 est celle du nord.
-- ============================================================================

update production.unite_culture u
set longueur_m = v.longueur
from (values
  (1, 104.0),
  (2, 104.7),
  (3, 105.3),
  (4, 106.0),
  (5, 106.6),
  (6, 107.3),
  (7, 107.9),
  (8, 108.6),
  (9, 109.3),
  (10, 109.9),
  (11, 110.6),
  (12, 111.2),
  (13, 111.9),
  (14, 112.5),
  (15, 113.2),
  (16, 113.8),
  (17, 114.5),
  (18, 115.2),
  (19, 115.8),
  (20, 116.5),
  (21, 117.1),
  (22, 117.8),
  (23, 118.4),
  (24, 119.1),
  (25, 119.8),
  (26, 120.4),
  (27, 121.1),
  (28, 121.7),
  (29, 122.4),
  (30, 123.0),
  (31, 123.7),
  (32, 124.4),
  (33, 125.0),
  (34, 125.7),
  (35, 126.3),
  (36, 127.0),
  (37, 127.6),
  (38, 128.3),
  (39, 129.0),
  (40, 129.6),
  (41, 130.3),
  (42, 130.9),
  (43, 131.6),
  (44, 132.2),
  (45, 132.9),
  (46, 133.5),
  (47, 134.2),
  (48, 134.9),
  (49, 135.5),
  (50, 136.2),
  (51, 136.8),
  (52, 137.5),
  (53, 138.1),
  (54, 138.8),
  (55, 139.5),
  (56, 140.1),
  (57, 140.8),
  (58, 141.4),
  (59, 142.1),
  (60, 142.7),
  (61, 143.4),
  (62, 144.1),
  (63, 144.7),
  (64, 145.4),
  (65, 146.0),
  (66, 146.7),
  (67, 147.3),
  (68, 148.0),
  (69, 148.6),
  (70, 149.3),
  (71, 150.0),
  (72, 150.6),
  (73, 151.3),
  (74, 151.9),
  (75, 152.6),
  (76, 153.2),
  (77, 153.9),
  (78, 154.6),
  (79, 155.2),
  (80, 155.9),
  (81, 156.5),
  (82, 157.2),
  (83, 157.8),
  (84, 158.5),
  (85, 159.2),
  (86, 159.8),
  (87, 160.5),
  (88, 161.1),
  (89, 161.8),
  (90, 162.4),
  (91, 163.0)
) as v(ordre, longueur)
where u.ordre = v.ordre
  and u.parcelle_id = (select id from production.parcelle where code = 'P0023');


-- La longueur de la parcelle n'est plus qu'une indication : la vérité vit
-- désormais sur chaque planche.
update production.parcelle
set note = 'Parcelle en biseau : longueurs de planche de 104 m (nord) à '
           || '163 m (sud), portées par chaque unité de culture.'
where code = 'P0023';
