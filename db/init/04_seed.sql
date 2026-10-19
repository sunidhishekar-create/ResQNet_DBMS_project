-- =====================================================================
-- ResQNet: 04_seed.sql
-- Demo data: 6 users, 3 disasters, 13 locations, 8 incidents,
-- 10 resource types, 24 resources, 36 requests, 9 allocations.
-- All demo users share the password:  Demo@1234
-- (hashed with bcrypt via pgcrypto; compatible with Node bcrypt).
-- Identity IDs are deterministic because this runs on a fresh database.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- USERS: 1 admin, 2-3 dispatchers, 4-6 reporters
INSERT INTO users (full_name, email, password_hash, role) VALUES
 ('Asha Rao',    'admin@resqnet.test',       crypt('Demo@1234', gen_salt('bf', 10)), 'ADMIN'),
 ('Dev Kumar',   'dispatcher1@resqnet.test', crypt('Demo@1234', gen_salt('bf', 10)), 'DISPATCHER'),
 ('Meera Iyer',  'dispatcher2@resqnet.test', crypt('Demo@1234', gen_salt('bf', 10)), 'DISPATCHER'),
 ('Ravi Shetty', 'reporter1@resqnet.test',   crypt('Demo@1234', gen_salt('bf', 10)), 'REPORTER'),
 ('Anita Das',   'reporter2@resqnet.test',   crypt('Demo@1234', gen_salt('bf', 10)), 'REPORTER'),
 ('Imran Khan',  'reporter3@resqnet.test',   crypt('Demo@1234', gen_salt('bf', 10)), 'REPORTER');

-- DISASTERS
INSERT INTO disaster (name, disaster_type, status, start_date, end_date) VALUES
 ('Bengaluru Urban Floods 2026', 'FLOOD',     'ACTIVE', '2026-10-10', NULL),
 ('Uttarakhand Landslide 2026',  'LANDSLIDE', 'ACTIVE', '2026-10-14', NULL),
 ('Chennai Cyclone 2025',        'CYCLONE',   'CLOSED', '2025-11-02', '2025-11-09');

-- LOCATIONS (1-7 Bengaluru, 8-13 Uttarakhand)
INSERT INTO location (name, district, latitude, longitude) VALUES
 ('Whitefield',        'Bengaluru Urban', 12.969800, 77.750000),
 ('Koramangala',       'Bengaluru Urban', 12.935200, 77.624500),
 ('Hebbal',            'Bengaluru Urban', 13.035800, 77.597000),
 ('Electronic City',   'Bengaluru Urban', 12.839900, 77.677000),
 ('Bellandur',         'Bengaluru Urban', 12.930400, 77.678400),
 ('Yelahanka',         'Bengaluru Urban', 13.100700, 77.596300),
 ('Jayanagar',         'Bengaluru Urban', 12.930800, 77.583800),
 ('Chamoli',           'Chamoli',         30.404700, 79.321500),
 ('Joshimath',         'Chamoli',         30.555000, 79.564600),
 ('Rudraprayag',       'Rudraprayag',     30.284400, 78.981100),
 ('Dehradun',          'Dehradun',        30.316500, 78.032200),
 ('Srinagar Garhwal',  'Pauri Garhwal',   30.222000, 78.783000),
 ('Tambaram',          'Chengalpattu',    12.924900, 80.100000);

-- INCIDENTS (1-5 disaster 1, 6-8 disaster 2)
INSERT INTO incident (disaster_id, location_id, description, status) VALUES
 (1, 5,  'Lake overflow flooding apartments',        'IN_PROGRESS'),
 (1, 1,  'Waterlogging, roads blocked',              'IN_PROGRESS'),
 (1, 2,  'Stormwater drain overflow',                'OPEN'),
 (1, 3,  'Flyover underpass flooding',               'OPEN'),
 (1, 4,  'Low-lying colony submerged',               'OPEN'),
 (2, 8,  'Landslide blocks highway',                 'IN_PROGRESS'),
 (2, 9,  'Houses damaged by slope failure',          'OPEN'),
 (2, 10, 'Bridge washed away',                       'OPEN');

-- RESOURCE TYPES
INSERT INTO resource_type (name, category, unit, urgency_weight) VALUES
 ('Ambulance',      'MEDICAL',    'vehicle', 10),
 ('Medical Team',   'MEDICAL',    'team',     9),
 ('Medicine Kit',   'MEDICAL',    'kit',      7),
 ('Rescue Team',    'RESCUE',     'team',    10),
 ('Rescue Boat',    'RESCUE',     'boat',     9),
 ('Shelter Bed',    'SHELTER',    'bed',      7),
 ('Food Packet',    'FOOD_WATER', 'packet',   6),
 ('Drinking Water', 'FOOD_WATER', 'litre',    8),
 ('Transport Truck','TRANSPORT',  'truck',    5),
 ('Generator',      'EQUIPMENT',  'unit',     4);

-- RESOURCES (available_qty starts equal to total_qty; status set by trigger)
INSERT INTO resource (type_id, location_id, name, total_qty, available_qty)
SELECT rt.type_id, l.location_id, v.name, v.qty, v.qty
FROM (VALUES
 ('Ambulance',      'Hebbal',           'Hebbal Ambulance Fleet',        6),
 ('Ambulance',      'Whitefield',       'Whitefield Ambulance Pool',     4),
 ('Ambulance',      'Dehradun',         'Dehradun Ambulance Base',       5),
 ('Ambulance',      'Rudraprayag',      'Rudraprayag Ambulance',         2),
 ('Medical Team',   'Koramangala',      'Koramangala Medical Team A',    3),
 ('Medical Team',   'Joshimath',        'Joshimath Field Hospital Team', 2),
 ('Medical Team',   'Dehradun',         'Dehradun Medical Team',         3),
 ('Medicine Kit',   'Jayanagar',        'Jayanagar Medical Store',     200),
 ('Medicine Kit',   'Dehradun',         'Dehradun Medical Store',      150),
 ('Rescue Team',    'Bellandur',        'NDRF Bellandur Unit',           4),
 ('Rescue Team',    'Chamoli',          'NDRF Chamoli Unit',             3),
 ('Rescue Team',    'Dehradun',         'SDRF Dehradun',                 5),
 ('Rescue Boat',    'Yelahanka',        'Yelahanka Boat Depot',          8),
 ('Rescue Boat',    'Electronic City',  'Electronic City Boat Pool',     3),
 ('Shelter Bed',    'Jayanagar',        'Jayanagar Community Hall',    200),
 ('Shelter Bed',    'Srinagar Garhwal', 'Srinagar Relief Camp',        150),
 ('Shelter Bed',    'Whitefield',       'Whitefield Stadium Shelter',  300),
 ('Food Packet',    'Hebbal',           'Hebbal Food Center',          500),
 ('Food Packet',    'Dehradun',         'Dehradun Food Depot',         400),
 ('Drinking Water', 'Koramangala',      'Koramangala Water Tanker Depot', 5000),
 ('Drinking Water', 'Rudraprayag',      'Rudraprayag Water Stock',     2000),
 ('Transport Truck','Yelahanka',        'Yelahanka Logistics Hub',       6),
 ('Transport Truck','Dehradun',         'Dehradun Logistics',            4),
 ('Generator',      'Electronic City',  'Electronic City Generator Store', 10)
) AS v(type_name, loc_name, name, qty)
JOIN resource_type rt ON rt.name = v.type_name
JOIN location l       ON l.name  = v.loc_name;

-- EMERGENCY REQUESTS (seq = request_id). Requests 2/3 and 12/13 are
-- deliberate near-duplicates for the semantic duplicate-detection demo.
INSERT INTO emergency_request
       (incident_id, requested_by, type_id, qty_needed, severity, affected_people, description, created_at)
SELECT v.incident_id, v.reporter, rt.type_id, v.qty, v.severity, v.affected, v.descr,
       now() - (v.hours * INTERVAL '1 hour')
FROM (VALUES
 ( 1, 1, 4, 'Ambulance',       1,  10,   3, 'Three people injured after wall collapse near Bellandur lake, ambulance needed urgently', 5),
 ( 2, 1, 5, 'Rescue Boat',     2,   9,  12, 'Elderly couple and neighbours trapped on first floor of apartment, water rising rapidly', 6),
 ( 3, 1, 6, 'Rescue Boat',     1,   8,   6, 'Senior citizens stuck on the first floor as flood water keeps rising, need boat evacuation', 4),
 ( 4, 1, 4, 'Drinking Water',500,   6,  80, 'No clean drinking water for residents of lakeside apartments since morning', 9),
 ( 5, 2, 5, 'Shelter Bed',    40,   7,  40, 'Families displaced by waterlogging need temporary shelter near Whitefield', 12),
 ( 6, 2, 6, 'Food Packet',   100,   6,  40, 'Food packets required for displaced families sheltering at Whitefield school', 10),
 ( 7, 2, 4, 'Ambulance',       1,   9,   1, 'Pregnant woman in labour, road blocked by water, ambulance required', 3),
 ( 8, 2, 5, 'Medicine Kit',   30,   5,  60, 'Basic medicine kits needed at Whitefield relief shelter for fever and cuts', 8),
 ( 9, 3, 6, 'Rescue Team',     1,   8,   5, 'Five people trapped in basement parking as stormwater drain overflows', 2),
 (10, 3, 4, 'Medical Team',    1,   7,  10, 'Medical team needed for injured residents, several with minor injuries and hypothermia', 7),
 (11, 3, 5, 'Generator',       2,   4,  30, 'Power outage in Koramangala community, generator needed for water pumps', 14),
 (12, 4, 6, 'Ambulance',       1,  10,   2, 'Two people unconscious in a car submerged in the Hebbal flyover underpass', 1),
 (13, 4, 4, 'Rescue Team',     1,  10,   2, 'Car submerged in Hebbal underpass with people inside, rescue divers needed', 1),
 (14, 4, 5, 'Transport Truck', 2,   5,   0, 'Trucks required to move relief supplies to Hebbal, roads partially open', 16),
 (15, 5, 6, 'Rescue Boat',     3,   9,  45, 'Entire low-lying colony in Electronic City submerged, residents on rooftops', 5),
 (16, 5, 4, 'Food Packet',   200,   7,  60, 'Residents stranded on rooftops need food packets by boat', 4),
 (17, 5, 5, 'Medical Team',    1,   8,  20, 'Diabetic and elderly patients stranded without medication in Electronic City', 6),
 (18, 5, 6, 'Shelter Bed',    80,   6,  80, 'Shelter needed for evacuated colony residents, capacity at community hall nearly full', 3),
 (19, 6, 4, 'Rescue Team',     2,  10,  15, 'Landslide blocked Chamoli highway, vehicles and passengers buried under debris', 4),
 (20, 6, 5, 'Ambulance',       2,  10,   6, 'Injured travellers pulled from landslide debris, ambulances needed at Chamoli', 3),
 (21, 6, 6, 'Transport Truck', 1,   5,   0, 'Truck required to carry earth-moving equipment and relief supplies to Chamoli', 11),
 (22, 6, 4, 'Food Packet',   150,   6,  70, 'Hundreds of travellers stranded on Chamoli highway, food needed', 8),
 (23, 7, 5, 'Shelter Bed',   100,   8, 100, 'Houses cracked and unsafe in Joshimath, families need shelter immediately', 9),
 (24, 7, 6, 'Medical Team',    1,   7,  25, 'Injured villagers in Joshimath need medical team, hospital road cut off', 7),
 (25, 7, 4, 'Drinking Water',800,   7, 120, 'Water pipeline damaged in Joshimath, residents without drinking water', 13),
 (26, 7, 5, 'Rescue Team',     1,   9,   4, 'Four people trapped inside collapsed house in Joshimath', 2),
 (27, 8, 6, 'Rescue Team',     1,   9,   8, 'Bridge washed away at Rudraprayag, eight villagers stranded on the far bank', 6),
 (28, 8, 4, 'Ambulance',       1,   8,   2, 'Two villagers injured, bridge washed away, ambulance needed on near side', 5),
 (29, 8, 5, 'Medicine Kit',   50,   6,  90, 'Medicine kits required for cut-off villages near Rudraprayag', 15),
 (30, 8, 6, 'Food Packet',   100,   6,  90, 'Food shortage in cut-off villages after bridge collapse', 18),
 (31, 3, 4, 'Shelter Bed',    30,   5,  30, 'Families in Koramangala low-lying lanes request temporary shelter', 20),
 (32, 1, 5, 'Medical Team',    1,   9,  15, 'Several flood victims with fractures and infections at Bellandur need doctors', 3),
 (33, 2, 6, 'Drinking Water',300,   5,  40, 'Drinking water needed at Whitefield shelter', 22),
 (34, 4, 4, 'Medicine Kit',   20,   4,  10, 'First-aid kits for volunteers working at Hebbal underpass', 12),
 (35, 7, 6, 'Transport Truck', 2,   5,   0, 'Trucks needed to evacuate belongings and people from Joshimath', 10),
 (36, 5, 5, 'Generator',       3,   6,  45, 'Generators needed to restore lighting at Electronic City relief point', 8)
) AS v(seq, incident_id, reporter, type_name, qty, severity, affected, descr, hours)
JOIN resource_type rt ON rt.name = v.type_name
ORDER BY v.seq;

-- ALLOCATIONS through the real transactional function (user 2 = dispatcher1)
SELECT allocate_resource( 1, (SELECT resource_id FROM resource WHERE name = 'Hebbal Ambulance Fleet'),     1, 2);
SELECT allocate_resource( 7, (SELECT resource_id FROM resource WHERE name = 'Whitefield Ambulance Pool'),  1, 2);
SELECT allocate_resource( 8, (SELECT resource_id FROM resource WHERE name = 'Jayanagar Medical Store'),   30, 2);
SELECT allocate_resource( 5, (SELECT resource_id FROM resource WHERE name = 'Whitefield Stadium Shelter'),25, 2);
SELECT allocate_resource( 6, (SELECT resource_id FROM resource WHERE name = 'Hebbal Food Center'),       100, 3);
SELECT allocate_resource(16, (SELECT resource_id FROM resource WHERE name = 'Hebbal Food Center'),       200, 3);
SELECT allocate_resource( 2, (SELECT resource_id FROM resource WHERE name = 'Yelahanka Boat Depot'),      2, 3);
SELECT allocate_resource(20, (SELECT resource_id FROM resource WHERE name = 'Dehradun Ambulance Base'),   1, 3);
SELECT allocate_resource(22, (SELECT resource_id FROM resource WHERE name = 'Dehradun Food Depot'),      150, 3);

-- Start with a clean audit trail so demos show only live activity
TRUNCATE audit_log RESTART IDENTITY;