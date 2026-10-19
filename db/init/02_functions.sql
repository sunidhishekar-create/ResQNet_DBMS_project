-- =====================================================================
-- ResQNet: 02_functions.sql
-- Stored functions: distance, priority score, candidate ranking,
-- and the atomic allocate / release transactions.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Great-circle distance in km between two coordinates
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION haversine_km(lat1 NUMERIC, lon1 NUMERIC, lat2 NUMERIC, lon2 NUMERIC)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT ROUND((2 * 6371 * asin(LEAST(1, sqrt(
               power(sin(radians((lat2 - lat1) / 2)), 2) +
               cos(radians(lat1)) * cos(radians(lat2)) *
               power(sin(radians((lon2 - lon1) / 2)), 2)
           ))))::NUMERIC, 2);
$$;

-- ---------------------------------------------------------------------
-- Request priority score (0-100). Describes the REQUEST only:
--   severity (max 40) + affected people (max 20) +
--   resource urgency (max 20) + waiting time (max 20, capped at 24 h)
-- Distance and availability belong to the request-resource pair and are
-- scored separately in rank_candidate_resources().
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_priority_score(p_request_id INT)
RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_score NUMERIC;
BEGIN
    SELECT ROUND((
               r.severity * 4
             + LEAST(r.affected_people, 100) * 0.2
             + rt.urgency_weight * 2
             + LEAST(EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600.0, 24) * (20.0 / 24)
           )::NUMERIC, 2)
      INTO v_score
      FROM emergency_request r
      JOIN resource_type rt ON rt.type_id = r.type_id
     WHERE r.request_id = p_request_id;

    IF v_score IS NULL THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;
    RETURN v_score;
END;
$$;

-- ---------------------------------------------------------------------
-- Candidate resources for a request, best match first.
-- match_score (0-100) = 60 * proximity + 40 * stock coverage
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rank_candidate_resources(p_request_id INT)
RETURNS TABLE (
    resource_id   INT,
    resource_name VARCHAR,
    location_name VARCHAR,
    available_qty INT,
    distance_km   NUMERIC,
    match_score   NUMERIC
)
LANGUAGE sql STABLE AS $$
    SELECT res.resource_id,
           res.name,
           rl.name,
           res.available_qty,
           d.dist,
           ROUND((60 * (1 - LEAST(d.dist, 100) / 100.0)
                + 40 * LEAST(res.available_qty::NUMERIC / r.qty_needed, 1))::NUMERIC, 2)
      FROM emergency_request r
      JOIN incident i   ON i.incident_id  = r.incident_id
      JOIN location il  ON il.location_id = i.location_id
      JOIN resource res ON res.type_id = r.type_id
                       AND res.available_qty > 0
                       AND res.status <> 'MAINTENANCE'
      JOIN location rl  ON rl.location_id = res.location_id
      CROSS JOIN LATERAL (
            SELECT haversine_km(il.latitude, il.longitude, rl.latitude, rl.longitude) AS dist
      ) d
     WHERE r.request_id = p_request_id
     ORDER BY 6 DESC, 5 ASC;
$$;

-- ---------------------------------------------------------------------
-- Atomic allocation. A PL/pgSQL function runs inside the caller's
-- transaction, so any RAISE EXCEPTION rolls back everything.
-- Lock order is always: request, then resource (prevents deadlocks).
-- Inventory and request status are updated by triggers (03_triggers.sql).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION allocate_resource(
    p_request_id  INT,
    p_resource_id INT,
    p_qty         INT,
    p_user_id     INT
) RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_req       emergency_request%ROWTYPE;
    v_res       resource%ROWTYPE;
    v_role      TEXT;
    v_allocated INT;
    v_dist      NUMERIC;
    v_score     NUMERIC;
    v_alloc_id  INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive';
    END IF;

    SELECT role INTO v_role FROM users WHERE user_id = p_user_id;
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'DISPATCHER') THEN
        RAISE EXCEPTION 'User % is not allowed to allocate resources', p_user_id;
    END IF;

    SELECT * INTO v_req FROM emergency_request WHERE request_id = p_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Request % not found', p_request_id;
    END IF;
    IF v_req.status NOT IN ('PENDING', 'PARTIAL') THEN
        RAISE EXCEPTION 'Request % is %, cannot allocate', p_request_id, v_req.status;
    END IF;

    SELECT * INTO v_res FROM resource WHERE resource_id = p_resource_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Resource % not found', p_resource_id;
    END IF;
    IF v_res.type_id <> v_req.type_id THEN
        RAISE EXCEPTION 'Resource type does not match the requested type';
    END IF;
    IF v_res.status = 'MAINTENANCE' THEN
        RAISE EXCEPTION 'Resource % is under maintenance', p_resource_id;
    END IF;
    IF p_qty > v_res.available_qty THEN
        RAISE EXCEPTION 'Insufficient stock: requested %, available %', p_qty, v_res.available_qty;
    END IF;

    SELECT COALESCE(SUM(qty_allocated), 0) INTO v_allocated
      FROM resource_allocation
     WHERE request_id = p_request_id AND status = 'ACTIVE';
    IF v_allocated + p_qty > v_req.qty_needed THEN
        RAISE EXCEPTION 'Over-allocation: request needs % more, tried to allocate %',
                        v_req.qty_needed - v_allocated, p_qty;
    END IF;

    SELECT haversine_km(il.latitude, il.longitude, rl.latitude, rl.longitude)
      INTO v_dist
      FROM incident i
      JOIN location il ON il.location_id = i.location_id
      JOIN location rl ON rl.location_id = v_res.location_id
     WHERE i.incident_id = v_req.incident_id;

    v_score := compute_priority_score(p_request_id);

    INSERT INTO resource_allocation
           (request_id, resource_id, allocated_by, qty_allocated, distance_km, priority_score)
    VALUES (p_request_id, p_resource_id, p_user_id, p_qty, v_dist, v_score)
    RETURNING allocation_id INTO v_alloc_id;

    RETURN v_alloc_id;
END;
$$;

-- ---------------------------------------------------------------------
-- Release an active allocation (stock is restored by trigger)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_allocation(p_allocation_id INT, p_user_id INT)
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_role       TEXT;
    v_request_id INT;
    v_status     TEXT;
BEGIN
    SELECT role INTO v_role FROM users WHERE user_id = p_user_id;
    IF v_role IS NULL OR v_role NOT IN ('ADMIN', 'DISPATCHER') THEN
        RAISE EXCEPTION 'User % is not allowed to release allocations', p_user_id;
    END IF;

    SELECT request_id INTO v_request_id FROM resource_allocation WHERE allocation_id = p_allocation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % not found', p_allocation_id;
    END IF;

    -- same lock order as allocate_resource: request first
    PERFORM 1 FROM emergency_request WHERE request_id = v_request_id FOR UPDATE;
    SELECT status INTO v_status FROM resource_allocation WHERE allocation_id = p_allocation_id FOR UPDATE;
    IF v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Allocation % is already %', p_allocation_id, v_status;
    END IF;

    UPDATE resource_allocation SET status = 'RELEASED' WHERE allocation_id = p_allocation_id;
END;
$$;