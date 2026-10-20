# Implementation and Testing (Phase 1)

This document explains everything built in Phase 1 and lists every test case
with its expected and actual result. It is written so the final project report
can be assembled from it. Sections map to the 12 documentation items in the
project requirements (see section 8).

Related documents: `01_objectives_requirements.md`, `02_er_diagram.md`,
`03_relational_schema.md` (relational schema, 3NF justification, data dictionary).

---

## 1. What Phase 1 delivered

| Area | Where |
|---|---|
| Environment (Docker, PostgreSQL 16 + pgvector) | `docker-compose.yml`, `.env.example` |
| Tables, keys, constraints (DDL) | `db/init/01_schema.sql` |
| Functions and the allocation transaction | `db/init/02_functions.sql` |
| Triggers (stock, status, audit) | `db/init/03_triggers.sql` |
| Demo data | `db/init/04_seed.sql` |
| ALTER / DROP demonstration | `db/demo/01_alter_drop_demo.sql` |
| Database test cases | `tests/phase1_db_checks.sql` |
| API test cases | `tests/phase1_api_tests.mjs` |
| Next.js app, DB connection | `app/lib/db.ts`, `app/app/api/health/route.ts` |
| Authentication and role guards | `app/lib/auth.ts`, `app/proxy.ts`, `app/app/api/auth/*`, `app/app/api/admin/users` |
| Request and allocation APIs | `app/lib/tx.ts`, `app/app/api/requests/*`, `app/app/api/allocations/*`, `app/app/api/meta` |

Seed data: 6 users, 3 disasters, 13 locations, 8 incidents, 10 resource types,
24 resources, 36 requests, 9 allocations.

---

## 2. Database choice and justification

The project requires SQL plus either a NoSQL or a vector database, chosen by the
nature of the data.

- **PostgreSQL (SQL):** requests, resources and allocations are structured,
  relational and transactional. Two dispatchers must never take the same last
  ambulance, which needs ACID transactions, row-level locking (`SELECT ... FOR UPDATE`),
  foreign keys and CHECK constraints.
- **pgvector (vector):** emergency descriptions are free text ("5 people trapped in
  building A"). Embeddings let the system find near-duplicate reports and similar
  past incidents by meaning, not keywords. This is implemented in Phase 2.
- **Why not MongoDB/Neo4j:** the data is highly relational and needs
  multi-row atomic updates; a NoSQL store would only hold logs and would be included
  "merely for technology demonstration", which the requirements warn against.
- **One engine:** pgvector runs inside the same PostgreSQL instance, so there is one
  database to run, back up and demo.

---

## 3. Requirement coverage

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Unique, non-CRUD problem | Done | Priority scoring, atomic allocation, semantic dedupe |
| 2 | 2-member team, both touch DB and app | In progress | Phase 1 (DB and API) done; Phase 2 adds vector DB and UI |
| 3 | SQL + vector DB | Phase 1: SQL; Phase 2: vector | `request_embedding` table exists |
| 4 | ER diagram, relational schema, constraints | Done | `02_er_diagram.md`, `03_relational_schema.md` |
| 5 | DDL: CREATE, ALTER, DROP, keys, constraints, indexes, views | CREATE/ALTER/DROP/keys/constraints done; indexes and views in Phase 2 | `01_schema.sql`, `01_alter_drop_demo.sql` |
| 6 | DML and JOIN, GROUP BY, HAVING, ORDER BY, aggregates, subqueries | Partly | INSERT/UPDATE/SELECT via the API; JOIN, ORDER BY, subquery and aggregate in the queue query; GROUP BY/HAVING in Phase 2 |
| 7 | 4 advanced SQL concepts + 1 vector | 4 done | Transactions, stored functions, triggers, row locking (see section 5); vector in Phase 2 |
| 8 | Embeddings and similarity search | Phase 2 | |
| 9 | Next.js web interface | API done; UI in Phase 2 | |
| 10 | Backend/API layer, no hard-coded credentials | Done | Route Handlers; `DATABASE_URL` and `JWT_SECRET` from `.env.local` |
| 11 | Authentication and roles (min. 2) | Done | 3 roles; backend checks |
| 12 | Data validation at the database level | Done | CHECK, UNIQUE, FK, NOT NULL; tests T1-T4 |
| 13 | Documentation | In progress | This file plus docs 01-03 |
| 14 | Git/GitHub with individual commits and README | In progress | |
| 15 | Demonstration | Phase 2 | |
| 16 | Originality | Done | |
| 17 | Beyond CRUD | Done | |

---

## 4. Design explanations

### 4.1 Schema and integrity
Ten tables; the request-resource many-to-many relationship is resolved by
`resource_allocation`, which holds its own attributes (quantity, distance, score,
status, timestamps). Integrity is enforced in the database, not only in the app:

| Rule | Mechanism |
|---|---|
| Severity 1 to 10, quantities positive | `CHECK` |
| Stock never negative or above total | `CHECK (available_qty >= 0 AND available_qty <= total_qty)` |
| Valid statuses and roles | `CHECK ... IN (...)` |
| One account per email, valid email shape | `UNIQUE` plus regex `CHECK` |
| No orphan records | Foreign keys; `ON DELETE RESTRICT` for operational history, `CASCADE` for embeddings, `SET NULL` for `audit_log.changed_by` |
| Date and time sanity | `end_date >= start_date`, `released_at >= allocated_at` |

### 4.2 Priority score and match score
Severity, affected people, resource urgency and waiting time describe a
**request**. Distance and availability describe a **request-resource pair**, so they
are scored separately.

- `compute_priority_score(request_id)`, range 0 to 100:
  severity x 4 (max 40) + min(affected people, 100) x 0.2 (max 20)
  + urgency weight x 2 (max 20) + min(waiting hours, 24) x 20/24 (max 20).
- `rank_candidate_resources(request_id)`: `match_score = 60 x proximity + 40 x stock coverage`,
  where proximity = 1 - min(distance_km, 100)/100 and coverage = min(available / needed, 1).
  Distance uses `haversine_km`, a great-circle formula.
- Because waiting time counts, an older severity-7 request can outrank a fresh
  severity-9 one. This is intended: it stops low-severity requests from starving.

### 4.3 The allocation transaction
`allocate_resource(request_id, resource_id, qty, user_id)`:
1. Checks the user is ADMIN or DISPATCHER.
2. Locks the request row, then the resource row (`FOR UPDATE`). The lock order is always
   request then resource, which prevents deadlocks.
3. Validates: request is PENDING or PARTIAL, resource type matches, resource is not under
   maintenance, quantity is within available stock and within the remaining need.
4. Computes distance and priority score and inserts the allocation.
Any failed check raises an exception and the whole transaction rolls back.
Concurrency: a second dispatcher asking for the same stock waits on the row lock, then
sees the reduced stock and is refused (test A37).

### 4.4 Triggers
| Trigger | Table | Effect |
|---|---|---|
| `allocation_effects` | `resource_allocation` after insert/update | Subtracts stock on allocate, restores it on release, then recomputes the request status |
| `allocation_guard` | `resource_allocation` before update | Stamps `released_at`, forbids re-activating a released allocation or editing quantity/request/resource |
| `resource_status_sync` | `resource` before insert/update | AVAILABLE, DEPLOYED or DEPLETED according to stock (MAINTENANCE untouched) |
| `audit_*` (6 triggers) | `emergency_request`, `resource`, `resource_allocation` | Writes old and new row as JSONB to `audit_log` |

`refresh_request_status` sets PENDING (nothing allocated), PARTIAL (some) or FULFILLED
(all), and sets or clears `fulfilled_at`. The last line of defence for stock is the
`CHECK` constraint, so even a direct INSERT that bypasses the function cannot over-allocate.

The audit trail records who acted: the API runs `set_config('app.user_id', ...)` at the
start of every transaction and the audit trigger reads it into `changed_by`.

### 4.5 Authentication and authorization
- Passwords: bcrypt hashes (`bcryptjs`). The seeded hashes are bcrypt too, so the same login works.
- Session: signed JWT (HS256, 8 hours) in an **httpOnly** cookie, so page scripts cannot read it.
  The signing secret is `JWT_SECRET` from `.env.local`.
- Two layers: `proxy.ts` rejects requests without a valid session (401 for the API, redirect to
  `/login` for pages); each route handler then calls `requireRole(...)` (401 or 403). Role checks
  therefore live in the backend.
- Public registration always creates a REPORTER, so nobody can sign up as an admin.
- Login returns the same error for an unknown email and a wrong password.
- Roles: ADMIN (everything), DISPATCHER (queue, candidates, allocate, release), REPORTER
  (create requests, see and cancel only their own).

### 4.6 Validation layers
Three layers, each catching different mistakes: **Zod** in the route (clear messages), the checks
inside the **database functions** (business rules), and the **table constraints** (final authority).
`errorResponse()` translates PostgreSQL error codes (23514 check, 23503 foreign key, 23505 unique,
P0001 raised by our functions) into 400/409 responses.

### 4.7 Configuration
No credentials are in the source. The root `.env` feeds Docker; `app/.env.local` holds
`DATABASE_URL` and `JWT_SECRET`. Only `.env.example` and `.env.local.example` are committed.

---

## 5. Advanced database features implemented

| Concept | Where |
|---|---|
| Transactions with rollback | `allocate_resource`, `release_allocation`, `withTransaction` |
| Row-level locking | `SELECT ... FOR UPDATE` in `allocate_resource` and cancel |
| Stored functions | `haversine_km`, `compute_priority_score`, `rank_candidate_resources`, `allocate_resource`, `release_allocation`, `refresh_request_status` |
| Triggers | Section 4.4 |
| Audit trail | `audit_log` plus the audit triggers |
| Still to add in Phase 2 | Views, indexes with EXPLAIN ANALYZE, full-text search, vector similarity search |

---

## 6. Important queries

**Ranking candidate resources** (inside `rank_candidate_resources`): joins request, incident,
location and resource, computes the distance in a `LATERAL` subquery and orders by match score.
```sql
SELECT res.resource_id, res.name, rl.name, res.available_qty, d.dist,
       ROUND((60 * (1 - LEAST(d.dist, 100) / 100.0)
            + 40 * LEAST(res.available_qty::NUMERIC / r.qty_needed, 1))::NUMERIC, 2)
  FROM emergency_request r
  JOIN incident i   ON i.incident_id  = r.incident_id
  JOIN location il  ON il.location_id = i.location_id
  JOIN resource res ON res.type_id = r.type_id AND res.available_qty > 0
                   AND res.status <> 'MAINTENANCE'
  JOIN location rl  ON rl.location_id = res.location_id
  CROSS JOIN LATERAL (SELECT haversine_km(il.latitude, il.longitude,
                                          rl.latitude, rl.longitude) AS dist) d
 WHERE r.request_id = $1
 ORDER BY 6 DESC, 5 ASC;
```

**The prioritised queue** (`GET /api/requests`): four JOINs, a correlated aggregate subquery,
dynamic filters and ordering by the computed score.
```sql
SELECT r.request_id, r.status, r.severity, r.affected_people, r.qty_needed,
       rt.name AS resource_type, d.name AS disaster, l.name AS location,
       compute_priority_score(r.request_id) AS priority_score,
       COALESCE((SELECT SUM(a.qty_allocated) FROM resource_allocation a
                  WHERE a.request_id = r.request_id AND a.status = 'ACTIVE'), 0) AS qty_allocated
  FROM emergency_request r
  JOIN resource_type rt ON rt.type_id = r.type_id
  JOIN incident i ON i.incident_id = r.incident_id
  JOIN disaster d ON d.disaster_id = i.disaster_id
  JOIN location l ON l.location_id = i.location_id
 WHERE r.status IN ('PENDING', 'PARTIAL')
 ORDER BY priority_score DESC, r.created_at ASC;
```
GROUP BY, HAVING, aggregate and window-function queries are added in Phase 2
(`db/demo/02_queries.sql`).

---

## 7. Test cases

Results below were recorded during development. Before submission, re-run both suites on
the final build, capture screenshots (section 9) and update the "Actual" column if needed.

### 7.1 Database tests (`tests/phase1_db_checks.sql`)
Run (PowerShell, from the project root; every test is rolled back, so data is untouched):
```powershell
Get-Content tests\phase1_db_checks.sql | docker exec -i resqnet-db psql -U resqnet_user -d resqnet
```

| ID | Input | Expected | Actual |
|---|---|---|---|
| T1 | Insert a request with severity 11 | Rejected (check violation) | PASS |
| T2 | Insert a request with quantity -3 | Rejected (check violation) | PASS |
| T3 | Insert a user with an existing email | Rejected (unique violation) | PASS |
| T4 | Set `available_qty` above `total_qty` | Rejected (check violation) | PASS |
| T5 | Allocate 50 units when only 4 are available | Rejected "Insufficient stock" | PASS |
| T6 | Allocate 2 units to a request that needs 1 | Rejected "Over-allocation" | PASS |
| T7 | A REPORTER calls `allocate_resource` | Rejected "not allowed" | PASS |
| T8 | Valid allocation | Stock decremented, request FULFILLED, `fulfilled_at` set | PASS |
| T9 | Release that allocation | Stock restored, request back to PENDING | PASS |
| T10 | Request needing 2 with 1 allocated | Status PARTIAL | PASS |
| T11 | Set stock to 0 | Resource status DEPLETED (trigger) | PASS |
| T12 | After the actions above | Audit rows exist in `audit_log` | PASS |
| T13 | Severity-10 request vs severity-4 request | Higher score for severity 10, scores within 0 to 100 | PASS |

### 7.2 API tests (`tests/phase1_api_tests.mjs`)
Needs Node 18+ and the app running (`npm run dev` inside `app`) on a seeded database:
```powershell
node tests\phase1_api_tests.mjs
```
The script prints PASS or FAIL for each test and a total. It creates its own requests and
cleans up (releases and cancels them), so it can be re-run. Result recorded: **38 of 38 passed**.

| ID | Test | Expected |
|---|---|---|
| A01 | Health check reaches the database | 200 |
| A02 | Protected route without login | 401 |
| A03 | Login with wrong password | 401 |
| A04 | Admin login sets an httpOnly session cookie | 200 + HttpOnly |
| A05 | Admin lists users | 200, 6+ users |
| A06 | Reporter calls an admin-only route | 403 |
| A07 | Dispatcher calls an admin-only route | 403 |
| A08 | Register with an existing email | 409 |
| A09 | Register with a short password | 400 |
| A10 | Public registration creates a REPORTER only | 201 REPORTER |
| A11 | Forged session cookie | 401 |
| A12 | Logout clears the cookie | 200, cookie cleared |
| A13 | Lookup data for forms | 200, incidents and types |
| A14 | Create request with severity 11 | 400 |
| A15 | Create request with unknown incident (foreign key) | 400 |
| A16 | Create request with too short description | 400 |
| A17 | Reporter creates a request | 201 PENDING with a priority score |
| A18 | Another reporter's list does not contain it | id absent |
| A19 | Another reporter opens it directly | 404 |
| A20 | Dispatcher queue ordered by priority score | descending |
| A21 | Filter `min_severity=10` | all rows severity 10 |
| A22 | Invalid filter value | 400 |
| A23 | Reporter asks for candidate resources | 403 |
| A24 | Candidates ranked by match score | descending |
| A25 | Reporter tries to allocate | 403 |
| A26 | Allocate more than the available stock | 409 Insufficient stock |
| A27 | Allocate more than the request needs | 409 Over-allocation |
| A28 | Dispatcher allocates the top candidate | 200 FULFILLED, stock reduced by 1 |
| A29 | Allocate to an already fulfilled request | 409 |
| A30 | Detail shows one ACTIVE allocation and `fulfilled_at` | as stated |
| A31 | Release the allocation | 200 RELEASED |
| A32 | Release reopens the request (trigger) | PENDING, `fulfilled_at` null |
| A33 | Release the same allocation twice | 409 |
| A34 | Reporter cancels someone else's request | 404 |
| A35 | Reporter cancels their own pending request | 200 CANCELLED |
| A36 | Cancel an already cancelled request | 409 |
| A37 | Two dispatchers allocate the same stock at the same instant | one 200 and one 409 |
| A38 | Stock is back to its original level after cleanup | original value |

### 7.3 Schema change demonstration (`db/demo/01_alter_drop_demo.sql`)
Run: `Get-Content db\demo\01_alter_drop_demo.sql | docker exec -i resqnet-db psql -U resqnet_user -d resqnet`

It shows `ALTER TABLE ... ADD COLUMN`, `ADD CONSTRAINT` (and the constraint rejecting a bad
phone number), `ALTER COLUMN` (type and default), `RENAME COLUMN`, `CREATE/ALTER/DROP INDEX`,
`CREATE/DROP VIEW`, `CREATE/ALTER/DROP TABLE`, and `DROP CONSTRAINT`/`DROP COLUMN`. It ends by
restoring the original schema. Result: PASS.

---

## 8. Mapping to the final report (12 items)

| Report section | Take it from |
|---|---|
| Objectives | `01_objectives_requirements.md` |
| Functional requirements | `01_objectives_requirements.md` |
| ER diagram | `02_er_diagram.md` and `docs/er_diagram.png` |
| Relational schema | `03_relational_schema.md` section 1 |
| Database choice and justification | Section 2 of this file |
| Data dictionary | `03_relational_schema.md` section 5 |
| SQL / vector implementation | Sections 4 and 5 here, plus the Phase 2 vector pipeline |
| Important queries | Section 6 here, plus Phase 2 queries |
| System architecture | Phase 2 diagram. Flow: Browser, Next.js (proxy + Route Handlers), `pg` pool, PostgreSQL (with pgvector) |
| Application screenshots | Phase 2 UI |
| Testing results | Section 7 here, plus UI tests |
| Conclusion | Write at the end |

---

## 9. Screenshots to capture (save in `docs/screenshots/`)

| File name | What |
|---|---|
| `01_docker_running.png` | `docker ps` showing `resqnet-db` |
| `02_tables.png` | `\dt` with the 10 tables |
| `03_table_constraints.png` | `\d emergency_request` (checks and foreign keys) |
| `04_functions.png` | `\df` (the functions) |
| `05_db_tests.png` | The `PASS T1` to `PASS T13` output |
| `06_alter_drop_demo.png` | ALTER/DROP demo output |
| `07_health_check.png` | `/api/health` in the browser |
| `08_api_tests.png` | `node tests\phase1_api_tests.mjs` ending in `38/38 passed` |
| `09_auth_401_403.png` | The 401 and 403 role checks |
| `10_queue_and_candidates.png` | The prioritised queue and ranked candidates |
| `11_allocate_release.png` | Allocate, the duplicate 409, and release |
| `12_audit_log.png` | `SELECT * FROM audit_log ORDER BY log_id DESC LIMIT 10;` showing `changed_by` |

---

## 10. Still to do (Phase 2)

Indexes with EXPLAIN ANALYZE, views, full-text search, the remaining queries (GROUP BY,
HAVING, subqueries, window functions), the vector pipeline, the UI, the admin APIs with a
working DELETE, the architecture diagram, UI test cases, and the final report. Details are in the
README task list.