-- =====================================================================
-- ResQNet: 01_schema.sql
-- DDL: extensions, tables, primary/foreign keys, constraints.
-- Runs automatically on first container start (docker-entrypoint-initdb.d).
-- Indexes, views and full-text search are added in later files.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- ---------------------------------------------------------------------
-- USERS: authentication and roles
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL CHECK (length(trim(full_name)) > 0),
    email         VARCHAR(255) NOT NULL UNIQUE
                  CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    password_hash TEXT NOT NULL,
    role          VARCHAR(20) NOT NULL DEFAULT 'REPORTER'
                  CHECK (role IN ('ADMIN', 'DISPATCHER', 'REPORTER')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- DISASTER
-- ---------------------------------------------------------------------
CREATE TABLE disaster (
    disaster_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(150) NOT NULL UNIQUE,
    disaster_type VARCHAR(30) NOT NULL
                  CHECK (disaster_type IN ('FLOOD', 'EARTHQUAKE', 'FIRE', 'CYCLONE', 'LANDSLIDE', 'OTHER')),
    status        VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
                  CHECK (status IN ('ACTIVE', 'CONTAINED', 'CLOSED')),
    start_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date      DATE,
    CONSTRAINT chk_disaster_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

-- ---------------------------------------------------------------------
-- LOCATION
-- ---------------------------------------------------------------------
CREATE TABLE location (
    location_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    district    VARCHAR(100) NOT NULL,
    latitude    NUMERIC(9,6) NOT NULL CHECK (latitude  BETWEEN -90  AND 90),
    longitude   NUMERIC(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT uq_location_name_district UNIQUE (name, district)
);

-- ---------------------------------------------------------------------
-- INCIDENT: a disaster at a location
-- ---------------------------------------------------------------------
CREATE TABLE incident (
    incident_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    disaster_id INT NOT NULL REFERENCES disaster(disaster_id) ON DELETE RESTRICT,
    location_id INT NOT NULL REFERENCES location(location_id) ON DELETE RESTRICT,
    description TEXT,
    status      VARCHAR(20) NOT NULL DEFAULT 'OPEN'
                CHECK (status IN ('OPEN', 'IN_PROGRESS', 'RESOLVED')),
    reported_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- RESOURCE_TYPE
-- ---------------------------------------------------------------------
CREATE TABLE resource_type (
    type_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           VARCHAR(80) NOT NULL UNIQUE,
    category       VARCHAR(30) NOT NULL
                   CHECK (category IN ('MEDICAL', 'RESCUE', 'SHELTER', 'FOOD_WATER', 'TRANSPORT', 'EQUIPMENT')),
    unit           VARCHAR(20) NOT NULL DEFAULT 'unit',
    urgency_weight INT NOT NULL DEFAULT 5 CHECK (urgency_weight BETWEEN 1 AND 10)
);

-- ---------------------------------------------------------------------
-- RESOURCE: a stock of one type stationed at one location
-- ---------------------------------------------------------------------
CREATE TABLE resource (
    resource_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_id       INT NOT NULL REFERENCES resource_type(type_id) ON DELETE RESTRICT,
    location_id   INT NOT NULL REFERENCES location(location_id)  ON DELETE RESTRICT,
    name          VARCHAR(120) NOT NULL,
    total_qty     INT NOT NULL CHECK (total_qty >= 0),
    available_qty INT NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE'
                  CHECK (status IN ('AVAILABLE', 'DEPLOYED', 'DEPLETED', 'MAINTENANCE')),
    CONSTRAINT chk_resource_available CHECK (available_qty >= 0 AND available_qty <= total_qty)
);

-- ---------------------------------------------------------------------
-- EMERGENCY_REQUEST
-- ---------------------------------------------------------------------
CREATE TABLE emergency_request (
    request_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    incident_id     INT NOT NULL REFERENCES incident(incident_id)      ON DELETE RESTRICT,
    requested_by    INT NOT NULL REFERENCES users(user_id)             ON DELETE RESTRICT,
    type_id         INT NOT NULL REFERENCES resource_type(type_id)     ON DELETE RESTRICT,
    qty_needed      INT NOT NULL CHECK (qty_needed > 0),
    severity        INT NOT NULL CHECK (severity BETWEEN 1 AND 10),
    affected_people INT NOT NULL DEFAULT 1 CHECK (affected_people >= 0),
    description     TEXT NOT NULL CHECK (length(trim(description)) >= 5),
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING', 'PARTIAL', 'FULFILLED', 'CANCELLED')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    fulfilled_at    TIMESTAMPTZ,
    CONSTRAINT chk_request_fulfilled CHECK (fulfilled_at IS NULL OR fulfilled_at >= created_at)
);

-- ---------------------------------------------------------------------
-- RESOURCE_ALLOCATION: resolves the M:N between request and resource
-- ---------------------------------------------------------------------
CREATE TABLE resource_allocation (
    allocation_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id     INT NOT NULL REFERENCES emergency_request(request_id) ON DELETE RESTRICT,
    resource_id    INT NOT NULL REFERENCES resource(resource_id)         ON DELETE RESTRICT,
    allocated_by   INT NOT NULL REFERENCES users(user_id)                ON DELETE RESTRICT,
    qty_allocated  INT NOT NULL CHECK (qty_allocated > 0),
    distance_km    NUMERIC(8,2) CHECK (distance_km >= 0),
    priority_score NUMERIC(8,2),
    status         VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE', 'RELEASED')),
    allocated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    released_at    TIMESTAMPTZ,
    CONSTRAINT chk_alloc_released CHECK (released_at IS NULL OR released_at >= allocated_at)
);

-- ---------------------------------------------------------------------
-- AUDIT_LOG: no FK to audited tables, so history survives deletions
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    log_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id  INT,
    action     VARCHAR(10) NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_value  JSONB,
    new_value  JSONB,
    changed_by INT REFERENCES users(user_id) ON DELETE SET NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- REQUEST_EMBEDDING: pgvector data, 1:1 optional child of the request
-- ---------------------------------------------------------------------
CREATE TABLE request_embedding (
    request_id INT PRIMARY KEY REFERENCES emergency_request(request_id) ON DELETE CASCADE,
    embedding  vector(384) NOT NULL,
    model_name VARCHAR(80) NOT NULL DEFAULT 'all-MiniLM-L6-v2',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);