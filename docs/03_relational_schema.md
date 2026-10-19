# Relational Schema and Data Dictionary

Notation: **PK** primary key, *FK* foreign key (-> referenced table), UK unique.

## 1. Relational schema (ER to tables)

```
users(user_id PK, full_name, email UK, password_hash, role, created_at)
disaster(disaster_id PK, name UK, disaster_type, status, start_date, end_date)
location(location_id PK, name, district, latitude, longitude)   UK(name, district)
incident(incident_id PK, disaster_id FK->disaster, location_id FK->location,
         description, status, reported_at)
resource_type(type_id PK, name UK, category, unit, urgency_weight)
resource(resource_id PK, type_id FK->resource_type, location_id FK->location,
         name, total_qty, available_qty, status)
emergency_request(request_id PK, incident_id FK->incident, requested_by FK->users,
         type_id FK->resource_type, qty_needed, severity, affected_people,
         description, status, created_at, fulfilled_at)
resource_allocation(allocation_id PK, request_id FK->emergency_request,
         resource_id FK->resource, allocated_by FK->users, qty_allocated,
         distance_km, priority_score, status, allocated_at, released_at)
audit_log(log_id PK, table_name, record_id, action, old_value, new_value,
         changed_by FK->users, changed_at)
request_embedding(request_id PK/FK->emergency_request, embedding, model_name, created_at)
```

## 2. ER to relational mapping

| ER element | Mapping |
|---|---|
| Strong entities | One table each, surrogate integer PK (identity column) |
| 1:N relationships | FK on the "many" side |
| M:N EMERGENCY_REQUEST and RESOURCE | New table `resource_allocation` with two FKs plus its own attributes |
| 1:1 optional EMERGENCY_REQUEST and REQUEST_EMBEDDING | Child table whose PK is also the FK (`ON DELETE CASCADE`) |
| Audit trail | Standalone table, no FK to audited tables so history survives deletes |

## 3. Referential actions

| FK | ON DELETE | Reason |
|---|---|---|
| incident, resource, emergency_request, resource_allocation to parents | RESTRICT | Operational history must not vanish |
| request_embedding.request_id | CASCADE | Embedding is meaningless without its request |
| audit_log.changed_by | SET NULL | Keep log rows if a user is removed |

## 4. Normalization (3NF)

| Table | Justification |
|---|---|
| users | Every attribute depends only on `user_id`; email is a candidate key |
| disaster | Attributes describe the disaster only |
| location | Coordinates depend on the location, not on incidents or resources |
| incident | Disaster and place facts stay in their own tables, referenced by FK |
| resource_type | Urgency weight and unit stored once per type, not per resource or request |
| resource | Type details are not repeated; only stock figures and status live here |
| emergency_request | No resource or location details repeated; type and incident by FK |
| resource_allocation | Distance and score depend on the request-resource pair (the whole key), which is why they live here and not on either parent |
| audit_log | Append-only log; intentionally denormalised (JSONB snapshots) |
| request_embedding | Separated from the request so the large vector column does not bloat the hot table |

## 5. Data dictionary

### users
| Column | Type | Constraints | Description |
|---|---|---|---|
| user_id | INT identity | PK | Surrogate key |
| full_name | VARCHAR(100) | NOT NULL, not blank | Display name |
| email | VARCHAR(255) | NOT NULL, UNIQUE, regex CHECK | Login id |
| password_hash | TEXT | NOT NULL | bcrypt hash, never plaintext |
| role | VARCHAR(20) | NOT NULL, IN (ADMIN, DISPATCHER, REPORTER), default REPORTER | Access role |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | Registration time |

### disaster
| Column | Type | Constraints | Description |
|---|---|---|---|
| disaster_id | INT identity | PK | |
| name | VARCHAR(150) | NOT NULL, UNIQUE | e.g. "Kerala Floods 2026" |
| disaster_type | VARCHAR(30) | NOT NULL, IN (FLOOD, EARTHQUAKE, FIRE, CYCLONE, LANDSLIDE, OTHER) | Category |
| status | VARCHAR(20) | NOT NULL, IN (ACTIVE, CONTAINED, CLOSED), default ACTIVE | Lifecycle |
| start_date | DATE | NOT NULL, default today | |
| end_date | DATE | NULL, must be >= start_date | |

### location
| Column | Type | Constraints | Description |
|---|---|---|---|
| location_id | INT identity | PK | |
| name | VARCHAR(150) | NOT NULL | Area name |
| district | VARCHAR(100) | NOT NULL | Used for grouping |
| latitude | NUMERIC(9,6) | NOT NULL, -90..90 | |
| longitude | NUMERIC(9,6) | NOT NULL, -180..180 | |
| (name, district) | | UNIQUE | No duplicate places |

### incident
| Column | Type | Constraints | Description |
|---|---|---|---|
| incident_id | INT identity | PK | |
| disaster_id | INT | NOT NULL, FK disaster, RESTRICT | Parent disaster |
| location_id | INT | NOT NULL, FK location, RESTRICT | Where it happens |
| description | TEXT | NULL | |
| status | VARCHAR(20) | NOT NULL, IN (OPEN, IN_PROGRESS, RESOLVED), default OPEN | |
| reported_at | TIMESTAMPTZ | NOT NULL, default now() | |

### resource_type
| Column | Type | Constraints | Description |
|---|---|---|---|
| type_id | INT identity | PK | |
| name | VARCHAR(80) | NOT NULL, UNIQUE | e.g. Ambulance |
| category | VARCHAR(30) | NOT NULL, IN (MEDICAL, RESCUE, SHELTER, FOOD_WATER, TRANSPORT, EQUIPMENT) | |
| unit | VARCHAR(20) | NOT NULL, default 'unit' | Counting unit |
| urgency_weight | INT | NOT NULL, 1..10, default 5 | Input to priority score |

### resource
| Column | Type | Constraints | Description |
|---|---|---|---|
| resource_id | INT identity | PK | |
| type_id | INT | NOT NULL, FK resource_type, RESTRICT | |
| location_id | INT | NOT NULL, FK location, RESTRICT | Where it is stationed |
| name | VARCHAR(120) | NOT NULL | e.g. "Ambulance 1" |
| total_qty | INT | NOT NULL, >= 0 | Total stock |
| available_qty | INT | NOT NULL, 0 <= available <= total | Unallocated stock |
| status | VARCHAR(20) | NOT NULL, IN (AVAILABLE, DEPLOYED, DEPLETED, MAINTENANCE), default AVAILABLE | |

### emergency_request
| Column | Type | Constraints | Description |
|---|---|---|---|
| request_id | INT identity | PK | |
| incident_id | INT | NOT NULL, FK incident, RESTRICT | |
| requested_by | INT | NOT NULL, FK users, RESTRICT | Reporter |
| type_id | INT | NOT NULL, FK resource_type, RESTRICT | What is needed |
| qty_needed | INT | NOT NULL, > 0 | |
| severity | INT | NOT NULL, 1..10 | |
| affected_people | INT | NOT NULL, >= 0, default 1 | |
| description | TEXT | NOT NULL, at least 5 chars | Free text, embedded for semantic search |
| status | VARCHAR(20) | NOT NULL, IN (PENDING, PARTIAL, FULFILLED, CANCELLED), default PENDING | |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | Used for waiting time |
| fulfilled_at | TIMESTAMPTZ | NULL, >= created_at | Set by trigger |

### resource_allocation
| Column | Type | Constraints | Description |
|---|---|---|---|
| allocation_id | INT identity | PK | |
| request_id | INT | NOT NULL, FK emergency_request, RESTRICT | |
| resource_id | INT | NOT NULL, FK resource, RESTRICT | |
| allocated_by | INT | NOT NULL, FK users, RESTRICT | Dispatcher |
| qty_allocated | INT | NOT NULL, > 0 | |
| distance_km | NUMERIC(8,2) | NULL, >= 0 | Resource to request location |
| priority_score | NUMERIC(8,2) | NULL | Score at allocation time |
| status | VARCHAR(20) | NOT NULL, IN (ACTIVE, RELEASED), default ACTIVE | |
| allocated_at | TIMESTAMPTZ | NOT NULL, default now() | |
| released_at | TIMESTAMPTZ | NULL, >= allocated_at | |

### audit_log
| Column | Type | Constraints | Description |
|---|---|---|---|
| log_id | BIGINT identity | PK | |
| table_name | VARCHAR(50) | NOT NULL | Audited table |
| record_id | INT | NULL | PK value of changed row |
| action | VARCHAR(10) | NOT NULL, IN (INSERT, UPDATE, DELETE) | |
| old_value / new_value | JSONB | NULL | Row snapshots |
| changed_by | INT | NULL, FK users, SET NULL | Acting user |
| changed_at | TIMESTAMPTZ | NOT NULL, default now() | |

### request_embedding
| Column | Type | Constraints | Description |
|---|---|---|---|
| request_id | INT | PK, FK emergency_request, CASCADE | 1:1 with request |
| embedding | vector(384) | NOT NULL | all-MiniLM-L6-v2 embedding of the description |
| model_name | VARCHAR(80) | NOT NULL, default 'all-MiniLM-L6-v2' | Model used |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |