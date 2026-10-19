-- =====================================================================
-- ResQNet: 03_triggers.sql
-- 1. Allocation effects: stock decrement/restore + request status sync
-- 2. Allocation guard: auto released_at, no re-activation
-- 3. Resource status sync (DEPLETED / DEPLOYED / AVAILABLE)
-- 4. Generic audit trail (requests, resources, allocations)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Recalculate a request's status from its ACTIVE allocations
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_request_status(p_request_id INT)
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_need   INT;
    v_status TEXT;
    v_alloc  INT;
BEGIN
    SELECT qty_needed, status INTO v_need, v_status
      FROM emergency_request WHERE request_id = p_request_id;

    IF v_status = 'CANCELLED' THEN
        RETURN;
    END IF;

    SELECT COALESCE(SUM(qty_allocated), 0) INTO v_alloc
      FROM resource_allocation
     WHERE request_id = p_request_id AND status = 'ACTIVE';

    UPDATE emergency_request
       SET status = CASE WHEN v_alloc = 0      THEN 'PENDING'
                         WHEN v_alloc < v_need THEN 'PARTIAL'
                         ELSE 'FULFILLED' END,
           fulfilled_at = CASE WHEN v_alloc >= v_need THEN COALESCE(fulfilled_at, now())
                               ELSE NULL END
     WHERE request_id = p_request_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 1. After allocation insert/update: adjust stock, sync request status
--    The CHECK on resource.available_qty is the last line of defence:
--    even a direct INSERT that bypasses allocate_resource() cannot
--    drive stock below zero.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_allocation_effects()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status = 'ACTIVE' THEN
            UPDATE resource
               SET available_qty = available_qty - NEW.qty_allocated
             WHERE resource_id = NEW.resource_id;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'ACTIVE' AND NEW.status = 'RELEASED' THEN
            UPDATE resource
               SET available_qty = available_qty + OLD.qty_allocated
             WHERE resource_id = OLD.resource_id;
        END IF;
    END IF;

    PERFORM refresh_request_status(NEW.request_id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER allocation_effects
AFTER INSERT OR UPDATE ON resource_allocation
FOR EACH ROW EXECUTE FUNCTION trg_allocation_effects();

-- ---------------------------------------------------------------------
-- 2. Guard: stamp released_at, forbid re-activating or editing quantity
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_allocation_guard()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status = 'RELEASED' AND NEW.status = 'ACTIVE' THEN
        RAISE EXCEPTION 'A released allocation cannot be re-activated';
    END IF;
    IF NEW.qty_allocated <> OLD.qty_allocated
       OR NEW.resource_id <> OLD.resource_id
       OR NEW.request_id  <> OLD.request_id THEN
        RAISE EXCEPTION 'Allocation quantity, request and resource are immutable';
    END IF;
    IF NEW.status = 'RELEASED' AND OLD.status = 'ACTIVE' AND NEW.released_at IS NULL THEN
        NEW.released_at := now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER allocation_guard
BEFORE UPDATE ON resource_allocation
FOR EACH ROW EXECUTE FUNCTION trg_allocation_guard();

-- ---------------------------------------------------------------------
-- 3. Keep resource.status consistent with stock (except MAINTENANCE)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_resource_status()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status <> 'MAINTENANCE' THEN
        NEW.status := CASE WHEN NEW.available_qty = 0              THEN 'DEPLETED'
                           WHEN NEW.available_qty < NEW.total_qty  THEN 'DEPLOYED'
                           ELSE 'AVAILABLE' END;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER resource_status_sync
BEFORE INSERT OR UPDATE ON resource
FOR EACH ROW EXECUTE FUNCTION trg_resource_status();

-- ---------------------------------------------------------------------
-- 4. Generic audit trail. TG_ARGV[0] = name of the PK column.
--    The application sets the acting user per transaction with:
--      SELECT set_config('app.user_id', '<id>', true);
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_audit()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_row  JSONB;
    v_user INT;
BEGIN
    v_user := NULLIF(current_setting('app.user_id', true), '')::INT;
    v_row  := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;

    INSERT INTO audit_log (table_name, record_id, action, old_value, new_value, changed_by)
    VALUES (TG_TABLE_NAME,
            (v_row ->> TG_ARGV[0])::INT,
            TG_OP,
            CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END,
            v_user);
    RETURN NULL;
END;
$$;

CREATE TRIGGER audit_request_insdel AFTER INSERT OR DELETE ON emergency_request
FOR EACH ROW EXECUTE FUNCTION trg_audit('request_id');
CREATE TRIGGER audit_request_upd AFTER UPDATE ON emergency_request
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION trg_audit('request_id');

CREATE TRIGGER audit_resource_insdel AFTER INSERT OR DELETE ON resource
FOR EACH ROW EXECUTE FUNCTION trg_audit('resource_id');
CREATE TRIGGER audit_resource_upd AFTER UPDATE ON resource
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION trg_audit('resource_id');

CREATE TRIGGER audit_allocation_insdel AFTER INSERT OR DELETE ON resource_allocation
FOR EACH ROW EXECUTE FUNCTION trg_audit('allocation_id');
CREATE TRIGGER audit_allocation_upd AFTER UPDATE ON resource_allocation
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION trg_audit('allocation_id');