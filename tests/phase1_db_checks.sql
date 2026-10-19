-- =====================================================================
-- ResQNet: tests/phase1_db_checks.sql
-- Database-level test cases. Everything runs inside a transaction that is
-- rolled back, so the seeded data is untouched.
-- Run:  docker exec -i resqnet-db psql -U resqnet_user -d resqnet < tests/phase1_db_checks.sql
-- Each test prints NOTICE "PASS ..." or aborts with "FAILED ...".
-- Requires the seed data from db/init/04_seed.sql.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;

-- T1: severity outside 1..10 is rejected
DO $$ BEGIN
    INSERT INTO emergency_request (incident_id, requested_by, type_id, qty_needed, severity, description)
    VALUES (1, 4, 1, 1, 11, 'severity out of range');
    RAISE EXCEPTION 'T1 FAILED: severity 11 accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS T1: severity 11 rejected'; END $$;

-- T2: negative / zero quantity is rejected
DO $$ BEGIN
    INSERT INTO emergency_request (incident_id, requested_by, type_id, qty_needed, severity, description)
    VALUES (1, 4, 1, -3, 5, 'negative quantity');
    RAISE EXCEPTION 'T2 FAILED: negative qty accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS T2: negative quantity rejected'; END $$;

-- T3: duplicate email is rejected
DO $$ BEGIN
    INSERT INTO users (full_name, email, password_hash) VALUES ('Dup', 'admin@resqnet.test', 'x');
    RAISE EXCEPTION 'T3 FAILED: duplicate email accepted';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS T3: duplicate email rejected'; END $$;

-- T4: available_qty above total_qty is rejected
DO $$ BEGIN
    UPDATE resource SET available_qty = total_qty + 1 WHERE name = 'Rudraprayag Ambulance';
    RAISE EXCEPTION 'T4 FAILED: available > total accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS T4: available_qty > total_qty rejected'; END $$;

-- T5: allocating more than stock fails
DO $$ BEGIN
    PERFORM allocate_resource(20, (SELECT resource_id FROM resource WHERE name = 'Dehradun Ambulance Base'), 50, 2);
    RAISE EXCEPTION 'T5 FAILED: over-stock allocation accepted';
EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'T5 FAILED%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS T5: insufficient stock rejected (%)', SQLERRM;
END $$;

-- T6: allocating more than the request needs fails (request 28 needs 1)
DO $$ BEGIN
    PERFORM allocate_resource(28, (SELECT resource_id FROM resource WHERE name = 'Rudraprayag Ambulance'), 2, 2);
    RAISE EXCEPTION 'T6 FAILED: over-allocation accepted';
EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'T6 FAILED%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS T6: over-allocation rejected (%)', SQLERRM;
END $$;

-- T7: a REPORTER cannot allocate
DO $$ BEGIN
    PERFORM allocate_resource(28, (SELECT resource_id FROM resource WHERE name = 'Rudraprayag Ambulance'), 1, 4);
    RAISE EXCEPTION 'T7 FAILED: reporter allocated';
EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'T7 FAILED%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS T7: reporter blocked (%)', SQLERRM;
END $$;

-- T8: allocation decrements stock, fulfils the request, stamps fulfilled_at
DO $$
DECLARE v_avail INT; v_status TEXT; v_ful TIMESTAMPTZ; v_alloc INT;
BEGIN
    SELECT allocate_resource(28, (SELECT resource_id FROM resource WHERE name = 'Rudraprayag Ambulance'), 1, 2)
      INTO v_alloc;
    SELECT available_qty INTO v_avail FROM resource WHERE name = 'Rudraprayag Ambulance';
    SELECT status, fulfilled_at INTO v_status, v_ful FROM emergency_request WHERE request_id = 28;
    IF v_avail <> 1 OR v_status <> 'FULFILLED' OR v_ful IS NULL THEN
        RAISE EXCEPTION 'T8 FAILED: avail=%, status=%, fulfilled_at=%', v_avail, v_status, v_ful;
    END IF;
    RAISE NOTICE 'PASS T8: stock decremented to %, request FULFILLED', v_avail;

    -- T9: release restores stock and reopens the request
    PERFORM release_allocation(v_alloc, 2);
    SELECT available_qty INTO v_avail FROM resource WHERE name = 'Rudraprayag Ambulance';
    SELECT status, fulfilled_at INTO v_status, v_ful FROM emergency_request WHERE request_id = 28;
    IF v_avail <> 2 OR v_status <> 'PENDING' OR v_ful IS NOT NULL THEN
        RAISE EXCEPTION 'T9 FAILED: avail=%, status=%, fulfilled_at=%', v_avail, v_status, v_ful;
    END IF;
    RAISE NOTICE 'PASS T9: release restored stock to % and reopened request', v_avail;
END $$;

-- T10: partial allocation gives PARTIAL status (request 20 needs 2, has 1)
DO $$
DECLARE v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM emergency_request WHERE request_id = 20;
    IF v_status <> 'PARTIAL' THEN RAISE EXCEPTION 'T10 FAILED: status=%', v_status; END IF;
    RAISE NOTICE 'PASS T10: partially served request is PARTIAL';
END $$;

-- T11: depleting stock flips resource status to DEPLETED
DO $$
DECLARE v_status TEXT;
BEGIN
    PERFORM allocate_resource(19, (SELECT resource_id FROM resource WHERE name = 'NDRF Chamoli Unit'), 2, 2);
    UPDATE resource SET available_qty = 0 WHERE name = 'NDRF Chamoli Unit';
    SELECT status INTO v_status FROM resource WHERE name = 'NDRF Chamoli Unit';
    IF v_status <> 'DEPLETED' THEN RAISE EXCEPTION 'T11 FAILED: status=%', v_status; END IF;
    RAISE NOTICE 'PASS T11: zero stock marks resource DEPLETED';
END $$;

-- T12: audit log captured the changes above
DO $$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM audit_log;
    IF v_n < 5 THEN RAISE EXCEPTION 'T12 FAILED: only % audit rows', v_n; END IF;
    RAISE NOTICE 'PASS T12: % audit rows written by triggers', v_n;
END $$;

-- T13: priority score is within 0..100 and a higher severity scores higher
DO $$
DECLARE v_hi NUMERIC; v_lo NUMERIC;
BEGIN
    v_hi := compute_priority_score(12);   -- severity 10, ambulance
    v_lo := compute_priority_score(34);   -- severity 4, medicine kit
    IF v_hi <= v_lo OR v_hi > 100 OR v_lo < 0 THEN
        RAISE EXCEPTION 'T13 FAILED: hi=%, lo=%', v_hi, v_lo;
    END IF;
    RAISE NOTICE 'PASS T13: priority % (sev 10) > % (sev 4)', v_hi, v_lo;
END $$;

ROLLBACK;
\echo 'All Phase 1 database checks completed (changes rolled back).'