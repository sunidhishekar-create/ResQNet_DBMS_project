# ResQNet: Intelligent Disaster Response and Emergency Resource Allocation System

DBMS Experiential Learning 
## Problem
During disasters (floods, earthquakes, landslides) hundreds of emergency requests
arrive while limited resources (ambulances, medical teams, shelters, food, water)
are scattered across locations. ResQNet does not just store records: it ranks
requests by a priority score (severity, affected people, resource urgency, waiting
time), ranks candidate resources for each request (distance, stock), and allocates
them atomically so a resource can never be over-allocated, even when several
dispatchers act at once.

## Tech Stack
| Layer | Technology |
|---|---|
| Frontend | Next.js 16 (App Router, TypeScript, Tailwind) |
| Backend/API | Next.js Route Handlers + `proxy.ts` |
| SQL DB | PostgreSQL 16 (raw SQL via `pg`, no ORM) |
| Vector DB | pgvector (same PostgreSQL instance) |
| Auth | bcryptjs + JWT (jose) in an httpOnly cookie; roles ADMIN, DISPATCHER, REPORTER |
| Validation | Zod in the API, CHECK/UNIQUE/FK constraints in the database |
| Dev environment | Docker Compose |
| Version control | Git + GitHub |

**Database justification:** PostgreSQL holds the structured, transactional data
(requests, resources, allocations) because it needs ACID guarantees, row locking
and constraints. pgvector holds embeddings of the free-text emergency descriptions
for semantic duplicate detection and similar-incident retrieval. One PostgreSQL
instance means one database to run, back up and demo.

## Documentation Map
| Read | For |
|---|---|
| `docs/01_objectives_requirements.md` | Objectives, roles, functional requirements |
| `docs/02_er_diagram.md` | ER diagram (Mermaid, renders on GitHub) |
| `docs/03_relational_schema.md` | Relational schema, 3NF justification, data dictionary |
| `docs/04_implementation_and_testing.md` | **Explains everything built in Phase 1**, requirement coverage, important queries, every test case (T1-T13, A01-A38), screenshot checklist, mapping to the final report |
| `docs/screenshots/` | Evidence for the report |

## Team and Work Split
Work is done in two sequential phases.

| Phase | Owner | Scope |
|---|---|---|
| 1 | Sunidhi | Repo and environment, ER diagram, relational schema, data dictionary, DDL with constraints, ALTER/DROP demo, functions, atomic allocation, triggers, seed data, DB and API tests, Next.js scaffold, DB connection, authentication and role guards, request and allocation APIs |
| 2 | Poojitha | Indexes and EXPLAIN ANALYZE, views, full-text search, important queries, vector pipeline, UI pages and dashboards, admin APIs (including DELETE), UI test cases, concurrency demo, screenshots, architecture diagram, final documentation, demo preparation |

## Prerequisites (Windows)
Git, Node.js LTS (v20+), Docker Desktop (WSL 2 backend), VS Code.

## Quick Start
```powershell
git clone https://github.com/<user>/ResQNet_DBMS_project.git
cd ResQNet_DBMS_project

# 1. Database (root .env is for Docker)
copy .env.example .env                  # edit the password if you like
docker compose up -d                    # runs db/init/*.sql on first start
docker ps                               # resqnet-db should be Up

# 2. Web app
cd app
npm install
copy .env.local.example .env.local      # then edit .env.local, see below
npm run dev                             # http://localhost:3000
```

**`app\.env.local` must contain:**
```
DATABASE_URL=postgresql://resqnet_user:<POSTGRES_PASSWORD from root .env>@localhost:5432/resqnet
JWT_SECRET=<a long random string>
```
Generate a secret with:
```powershell
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```
The password in `DATABASE_URL` must match `POSTGRES_PASSWORD` in the root `.env`.
Neither `.env` nor `.env.local` is committed; only the `.example` files are.

**Check it works:** open http://localhost:3000/api/health. It should return
`{"ok":true,"requests":36}`.

**Reset the database:** init scripts only run when the data volume is first created.
After changing any file in `db/init/`:
```powershell
docker compose down -v
docker compose up -d
```

Do not run `npm audit fix --force`; it can break the Next.js install.

## Running the Tests
Run these from the **project root** (not from inside `app`).

```powershell
# Database tests: T1-T13, all rolled back so data is untouched
Get-Content tests\phase1_db_checks.sql | docker exec -i resqnet-db psql -U resqnet_user -d resqnet

# ALTER / DROP demonstration (restores the schema at the end)
Get-Content db\demo\01_alter_drop_demo.sql | docker exec -i resqnet-db psql -U resqnet_user -d resqnet

# API tests: A01-A38 (the app must be running with npm run dev in another terminal)
node tests\phase1_api_tests.mjs
```
Expected: `PASS T1` to `PASS T13`, and `38/38 passed`. The API tests create their own
requests and clean up after themselves, so they can be re-run. Test descriptions and
expected results are in `docs/04_implementation_and_testing.md`.

## Demo Logins
All seeded users share the password `Demo@1234`.

| Email | Role |
|---|---|
| admin@resqnet.test | ADMIN |
| dispatcher1@resqnet.test, dispatcher2@resqnet.test | DISPATCHER |
| reporter1@resqnet.test, reporter2@resqnet.test, reporter3@resqnet.test | REPORTER |

Public registration always creates a REPORTER.

## Repository Layout
```
db/init/    SQL that runs automatically on first DB start, in filename order
            01_schema.sql      tables, keys, constraints, pgvector extension
            02_functions.sql   haversine_km, compute_priority_score,
                               rank_candidate_resources, allocate_resource, release_allocation
            03_triggers.sql    stock and status sync, audit trail
            04_seed.sql        demo data (36 requests, 24 resources, 6 users)
db/demo/    SQL run manually for demos (01_alter_drop_demo.sql)
app/        Next.js application
            lib/db.ts, lib/auth.ts, lib/tx.ts, proxy.ts, app/api/...
docs/       objectives, ER diagram, schema + data dictionary, implementation and testing, screenshots
tests/      phase1_db_checks.sql (database tests), phase1_api_tests.mjs (API tests)
```

## Database Overview
10 tables: `users`, `disaster`, `location`, `incident`, `resource_type`, `resource`,
`emergency_request`, `resource_allocation` (resolves the request-resource M:N),
`audit_log`, `request_embedding` (pgvector, empty until Phase 2).

Key behaviours implemented in the database:
- `allocate_resource(request, resource, qty, user)`: locks the request, then the resource
  (`FOR UPDATE`), validates role, type, stock and remaining need, inserts the allocation.
  Any error rolls the whole transaction back.
- Triggers keep `resource.available_qty`, `resource.status` and `emergency_request.status`
  / `fulfilled_at` consistent, and write every change to `audit_log`.
- Priority score (0-100) = severity (40) + affected people (20) + resource urgency (20)
  + waiting time (20, capped at 24 h). Match score for a request-resource pair =
  60% proximity + 40% stock coverage.

**Open a psql session:** `docker exec -it resqnet-db psql -U resqnet_user -d resqnet`
(`\dt` tables, `\d tablename` columns and constraints, `\df` functions, `\q` quit).

## API Reference
All routes except health, login, register and logout need a valid session cookie.
Role checks are done in the backend with `requireRole()` in every handler.

| Method and path | Roles | Purpose |
|---|---|---|
| GET `/api/health` | public | App and DB connectivity |
| POST `/api/auth/register` | public | Sign up (creates a REPORTER) |
| POST `/api/auth/login` | public | Log in, sets the session cookie |
| POST `/api/auth/logout` | public | Clears the cookie |
| GET `/api/auth/me` | any | Current user |
| GET `/api/admin/users` | ADMIN | List users |
| GET `/api/meta` | any | Incidents and resource types for forms |
| POST `/api/requests` | any | Create an emergency request |
| GET `/api/requests` | any | Priority-ordered queue; filters `status` (OPEN default for staff, ALL, PENDING, PARTIAL, FULFILLED, CANCELLED), `disaster_id`, `type_id`, `min_severity`, `limit`, `offset`. Reporters only see their own |
| GET `/api/requests/[id]` | any | Detail and allocations (reporters: own only) |
| GET `/api/requests/[id]/candidates` | DISPATCHER, ADMIN | Ranked candidate resources |
| POST `/api/requests/[id]/allocate` | DISPATCHER, ADMIN | Body `{resource_id, qty}`, atomic |
| POST `/api/allocations/[id]/release` | DISPATCHER, ADMIN | Release an allocation |
| POST `/api/requests/[id]/cancel` | owner, DISPATCHER, ADMIN | Cancel a request with no active allocations |

Try it in PowerShell:
```powershell
$login = @{ email="dispatcher1@resqnet.test"; password="Demo@1234" } | ConvertTo-Json
Invoke-RestMethod -Uri http://localhost:3000/api/auth/login -Method Post -Body $login -ContentType "application/json" -SessionVariable d | Out-Null
(Invoke-RestMethod -Uri "http://localhost:3000/api/requests?limit=5" -WebSession $d).requests
```

## Troubleshooting
| Problem | Fix |
|---|---|
| `docker` not recognized, or "failed to connect to the docker API" | Install Docker Desktop and start it; wait for "Engine running"; open a new terminal |
| Port 5432 already in use | Set `POSTGRES_PORT=5433` in the root `.env`, change the port in `DATABASE_URL`, then `docker compose down -v` and `docker compose up -d` |
| `password authentication failed` | The password in `app\.env.local` does not match the root `.env`. If you changed the root one after the first start, run `docker compose down -v` then `up -d` |
| `/api/health` fails with `ECONNREFUSED` | `resqnet-db` is not running; check `docker ps` |
| `relation ... does not exist` | The schema did not load; `docker compose down -v`, `docker compose up -d`, then `docker logs resqnet-db` |
| `node tests\...` says module not found | You are inside `app`; `cd ..` to the project root |
| API tests say `fetch failed` | The app is not running; start `npm run dev` inside `app` |
| New `.sql` file in `db/init` was ignored | Init scripts run only on a fresh volume; rebuild, or pipe the file into psql |
| Git push gives 403 | Windows is using another GitHub account; clear it in Credential Manager (`git:https://github.com`) and sign in again |

## Project Status
**Phase 1 (Sunidhi)**
- [x] Repo, folder structure, Docker environment
- [x] Objectives and functional requirements
- [x] ER diagram
- [x] Relational schema and data dictionary
- [x] DDL with constraints; ALTER/DROP demo
- [x] Functions, allocation transaction, triggers
- [x] Seed data and database test cases
- [x] Next.js scaffold, DB connection, authentication and roles
- [x] Request-creation and allocation APIs
- [x] API test suite and implementation/testing document

**Phase 2 (Poojitha)**
- [ ] Indexes and EXPLAIN ANALYZE evidence
- [ ] Views
- [ ] Full-text search
- [ ] Important queries
- [ ] Vector embeddings and semantic search
- [ ] UI pages and dashboards
- [ ] Admin APIs (including DELETE)
- [ ] UI test cases, concurrency demo, screenshots, architecture diagram
- [ ] Final documentation and demo preparation

## Notes for <Poojitha> (Phase 2)

### Start here
1. Follow the Quick Start and run all three test commands above to confirm your
   machine matches (`PASS T1-T13`, `38/38 passed`).
2. Read `docs/04_implementation_and_testing.md`. It explains the design, how the
   allocation transaction and triggers work, and where each requirement stands.
3. Use your own git identity so your commits show your contribution.

### What already works
- The schema, functions, triggers and seed data load automatically with
  `docker compose up -d`.
- Login, roles, request creation, the prioritised queue, candidate ranking,
  allocate, release and cancel all work through the API.
- There is **no UI yet**. `proxy.ts` redirects unauthenticated page requests to
  `/login`, which does not exist until you build it.

### Conventions to keep
- **Every write goes through `withTransaction(userId, fn)` in `app/lib/tx.ts`.** It sets
  `app.user_id` so the audit triggers record who made the change.
- **Every route handler starts with `requireRole(...)`** from `app/lib/auth.ts`.
- Keep raw SQL (no ORM) and map database errors with `errorResponse()` from `tx.ts`.
- New SQL goes in numbered files: `db/init/05_...sql`, `06_...sql`. They run in order
  on a fresh volume. To apply one to a running database without wiping it:
  `Get-Content db\init\05_x.sql | docker exec -i resqnet-db psql -U resqnet_user -d resqnet`
- Never hard-code resource or request IDs in code; identity values can differ between
  machines. Look records up by name or use the API.
- Next.js 16 specifics: `middleware.ts` is now `proxy.ts`; `cookies()` and route `params`
  are async.

### Your task list
1. **Indexes** (`db/init/05_indexes.sql`): B-tree on `emergency_request(status, severity DESC)`,
   `resource(type_id, location_id)`, and the foreign keys the queue query uses. Show
   `EXPLAIN ANALYZE` before and after for the queue query and save screenshots in

Phase 1 is on main (tag handoff-1). Start with the README: setup steps, demo logins, API reference and your Phase 2 task list. Then read docs/04_implementation_and_testing.md, which explains everything done so far and lists all the tests. You’ll need Docker Desktop, Node 20+, Git and VS Code. Run docker compose up -d, then set up app/.env.local as the README says, and run node tests\phase1_api_tests.mjs to confirm it all works on your machine before you start. Use your own git identity so the commits show your contribution.