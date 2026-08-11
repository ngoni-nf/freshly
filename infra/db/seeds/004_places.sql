-- ---------------------------------------------------------------------------
-- Suburbs a client can type.
--
-- Only Johannesburg North is live, so only Johannesburg North has places. The
-- other metros get theirs when they open — seeding Cape Town suburbs now would
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
