-- =====================================================================
-- ResQNet: db/demo/01_alter_drop_demo.sql   (run manually, not on init)
-- Demonstrates ALTER and DROP. Re-runnable: it restores the schema
-- to its original state at the end.
-- Run:  docker exec -i resqnet-db psql -U resqnet_user -d resqnet < db/demo/01_alter_drop_demo.sql
-- =====================================================================

\echo '--- 1. ALTER TABLE ... ADD COLUMN / ADD CONSTRAINT'
ALTER TABLE users ADD COLUMN contact_phone VARCHAR(15);
ALTER TABLE users ADD CONSTRAINT chk_users_phone
      CHECK (contact_phone IS NULL OR contact_phone ~ '^[0-9+ -]{7,15}$');

\echo '--- constraint in action: invalid phone is rejected'
DO $$
BEGIN
    UPDATE users SET contact_phone = 'abc' WHERE user_id = 1;
    RAISE EXCEPTION 'phone constraint did not fire';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS: invalid phone rejected by CHECK';
END $$;

\echo '--- 2. ALTER COLUMN (type, default) and RENAME'
ALTER TABLE users ALTER COLUMN contact_phone TYPE VARCHAR(20);
ALTER TABLE users ALTER COLUMN contact_phone SET DEFAULT '';
ALTER TABLE users RENAME COLUMN contact_phone TO phone;

\echo '--- 3. CREATE / ALTER / DROP an index'
CREATE INDEX idx_demo_request_status ON emergency_request (status);
ALTER INDEX idx_demo_request_status RENAME TO idx_demo_req_status;
DROP INDEX idx_demo_req_status;

\echo '--- 4. CREATE / DROP a view'
CREATE VIEW v_demo_open_requests AS
    SELECT request_id, severity, status FROM emergency_request WHERE status IN ('PENDING', 'PARTIAL');
SELECT count(*) AS open_requests FROM v_demo_open_requests;
DROP VIEW v_demo_open_requests;

\echo '--- 5. CREATE / ALTER / DROP a scratch table'
CREATE TABLE demo_scratch (id INT PRIMARY KEY, note TEXT);
ALTER TABLE demo_scratch ADD COLUMN created_at TIMESTAMPTZ DEFAULT now();
DROP TABLE demo_scratch;

\echo '--- 6. DROP COLUMN / DROP CONSTRAINT: restore original schema'
ALTER TABLE users DROP CONSTRAINT chk_users_phone;
ALTER TABLE users DROP COLUMN phone;

\echo '--- done: schema restored'
\d users