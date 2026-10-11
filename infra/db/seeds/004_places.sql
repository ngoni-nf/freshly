-- ---------------------------------------------------------------------------
-- Suburbs a client can type.
--
-- Johannesburg North and Harare are live, so they have places. The other
-- metros get theirs when they open — seeding Cape Town suburbs now would
-- let autocomplete suggest Sea Point and then refuse the booking, which is the
-- exact failure the places table exists to prevent.
--
-- Popularity is a rough ordering of where the work actually is, not a
-- population figure. It only has to make the first suggestion the likely one.
-- ---------------------------------------------------------------------------

INSERT INTO places (service_area_id, name, postal_code, centroid, popularity)
SELECT a.id, v.name, v.postal_code,
       ST_SetSRID(ST_MakePoint(v.lng, v.lat), 4326)::geography, v.popularity
  FROM service_areas a
  CROSS JOIN (VALUES
    ('Sandton',        '2196', -26.1076, 28.0567, 100),
    ('Rosebank',       '2196', -26.1438, 28.0406,  95),
    ('Randburg',       '2194', -26.0936, 27.9756,  85),
    ('Fourways',       '2055', -26.0167, 28.0093,  80),
    ('Bryanston',      '2191', -26.0525, 28.0192,  75),
    ('Midrand',        '1685', -25.9992, 28.1263,  70),
    ('Melville',       '2109', -26.1747, 27.9990,  65),
    ('Parktown North', '2193', -26.1461, 28.0261,  60),
    ('Morningside',    '2057', -26.0770, 28.0567,  58),
    ('Craighall Park', '2196', -26.1233, 28.0125,  55),
    ('Illovo',         '2196', -26.1298, 28.0561,  54),
    ('Hyde Park',      '2196', -26.1236, 28.0356,  52),
    ('Rivonia',        '2128', -26.0553, 28.0605,  50),
    ('Sunninghill',    '2157', -26.0294, 28.0722,  48),
    ('Woodmead',       '2191', -26.0523, 28.0894,  46),
    ('Douglasdale',    '2021', -26.0359, 27.9942,  44),
    ('Northcliff',     '2195', -26.1490, 27.9508,  42),
    ('Greenside',      '2193', -26.1462, 27.9986,  40),
    ('Parkhurst',      '2193', -26.1387, 28.0086,  38),
    ('Blairgowrie',    '2194', -26.1114, 27.9976,  36),
    ('Ferndale',       '2194', -26.0917, 28.0009,  34),
    ('Bramley',        '2090', -26.1281, 28.0806,  32),
    ('Alexandra',      '2090', -26.1017, 28.1000,  30),
    ('Wynberg',        '2090', -26.1108, 28.0872,  28),
    ('Strijdom Park',  '2194', -26.0762, 27.9718,  26)
  ) AS v(name, postal_code, lat, lng, popularity)
 WHERE a.slug = 'jhb-north'
ON CONFLICT (service_area_id, name) DO UPDATE
  SET centroid   = EXCLUDED.centroid,
      postal_code = EXCLUDED.postal_code,
      popularity = EXCLUDED.popularity,
      is_active  = true;

-- Harare. Coordinates are OpenStreetMap place nodes, not estimates: a suburb a
-- few kilometres off would quietly misprice every travel fee quoted from it.
-- Zimbabwe has no postal codes. Sub-sections (Glen Norah A/B/C, Warren Park D)
-- are left out in favour of the suburb. Popularity is a rough guess at where
-- the work is; it only decides which suggestion comes first.
INSERT INTO places (service_area_id, name, postal_code, centroid, popularity)
SELECT a.id, v.name, NULL,
       ST_SetSRID(ST_MakePoint(v.lng, v.lat), 4326)::geography, v.popularity
  FROM service_areas a
  CROSS JOIN (VALUES
    ('Arundel', -17.7648, 31.0444, 40),
    ('Avondale', -17.7932, 31.0361, 100),
    ('Avondale West', -17.7975, 31.0288, 40),
    ('Belvedere', -17.828, 31.0105, 78),
    ('Bluff Hill', -17.7703, 30.9885, 40),
    ('Borrowdale', -17.7573, 31.1081, 98),
    ('Braeside', -17.8422, 31.0647, 40),
    ('Budiriro', -17.8971, 30.9348, 72),
    ('Caledonia', -17.8277, 31.2426, 40),
    ('Chinamano', -17.9035, 31.1661, 40),
    ('Chisipite', -17.7885, 31.1185, 80),
    ('Chizhanje', -17.8454, 31.178, 40),
    ('Cold Comfort', -17.8377, 30.9497, 40),
    ('Cranborne', -17.8516, 31.084, 40),
    ('Damofalls Park', -17.8398, 31.2255, 40),
    ('Domboramwari', -17.9073, 31.1445, 40),
    ('Dzivarasekwa', -17.8089, 30.9302, 40),
    ('Eastlea', -17.815, 31.0786, 84),
    ('Eyestone Park', -17.9159, 31.05, 40),
    ('Glen Norah', -17.905, 30.9689, 40),
    ('Glen View', -17.9094, 30.9434, 72),
    ('Glenwood', -17.9246, 31.1409, 40),
    ('Glenwood Park', -17.9183, 31.1408, 40),
    ('Greendale', -17.8128, 31.1279, 90),
    ('Greystone Park', -17.7427, 31.1153, 40),
    ('Gunhill', -17.7931, 31.0675, 40),
    ('Hatcliffe', -17.6947, 31.1089, 40),
    ('Hatfield', -17.8784, 31.0858, 74),
    ('Highfield', -17.8913, 30.9861, 72),
    ('Highlands', -17.7981, 31.0902, 92),
    ('Hopley', -17.9343, 30.9922, 40),
    ('Jacha', -17.878, 31.1424, 40),
    ('Kambuzuma', -17.8531, 30.9736, 40),
    ('Kuwadzana', -17.8281, 30.9188, 70),
    ('Lewisam', -17.7957, 31.1105, 40),
    ('Mabelreign', -17.7823, 31.0008, 86),
    ('Mabvuku', -17.8347, 31.1877, 40),
    ('Magada', -17.9157, 31.1682, 40),
    ('Makomo', -17.8821, 31.1312, 40),
    ('Mandara', -17.7938, 31.1467, 40),
    ('Marlborough', -17.7453, 31.0162, 88),
    ('Matapi', -17.8556, 31.0425, 40),
    ('Mbare', -17.8633, 31.0345, 70),
    ('Milton Park', -17.8165, 31.0225, 82),
    ('Monavale', -17.8028, 31.0161, 40),
    ('Mount Pleasant', -17.7733, 31.0528, 95),
    ('Mufakose', -17.8676, 30.9251, 40),
    ('Muguta', -17.8744, 31.1329, 40),
    ('Northwood', -17.7543, 31.0446, 40),
    ('Nyikavanhu', -17.9116, 31.169, 40),
    ('Overspill', -17.8816, 31.161, 40),
    ('Prospect', -17.8972, 31.0555, 40),
    ('Saturday Retreat', -17.9502, 30.9547, 40),
    ('Southlea Park', -17.9662, 30.9835, 40),
    ('Southview Park', -17.9362, 30.9696, 40),
    ('Stopover', -17.919, 31.1658, 40),
    ('Strathaven', -17.797, 31.0228, 40),
    ('Sunningdale', -17.8685, 31.0541, 40),
    ('Tafara', -17.8411, 31.204, 40),
    ('The Grange', -17.7756, 31.1372, 40),
    ('Tynwald', -17.801, 30.9684, 40),
    ('Ushewokunzwe', -17.9614, 30.9395, 40),
    ('Vainona', -17.7554, 31.0778, 40),
    ('Warren Park', -17.8333, 30.9622, 70),
    ('Waterfalls', -17.8972, 31.0203, 76),
    ('Westgate', -17.7654, 30.9739, 40),
    ('Westlea', -17.8205, 30.9788, 40),
    ('Westwood', -17.8505, 30.9804, 40),
    ('Zimre Park', -17.8656, 31.2109, 40),
    ('Zinyengere', -17.9111, 31.1604, 40)
  ) AS v(name, lat, lng, popularity)
 WHERE a.slug = 'hre-metro'
   AND ST_Covers(a.boundary::geometry, ST_SetSRID(ST_MakePoint(v.lng, v.lat), 4326))
ON CONFLICT (service_area_id, name) DO UPDATE
  SET centroid   = EXCLUDED.centroid,
      popularity = EXCLUDED.popularity,
      is_active  = true;
