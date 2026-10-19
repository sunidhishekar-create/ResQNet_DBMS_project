# ResQNet: Intelligent Disaster Response and Emergency Resource Allocation System

DBMS Experiential Learning – Level 3 Project, PES University

## Problem
During disasters (floods, earthquakes, fires), hundreds of emergency requests
arrive while limited resources (ambulances, medical teams, shelters, food,
water) are scattered across locations. ResQNet matches resources to requests
using severity, affected people, distance, urgency, waiting time and
availability, instead of just storing records.

## Tech Stack
| Layer | Technology |
|---|---|
| Frontend | Next.js (App Router) |
| Backend/API | Next.js Route Handlers |
| SQL DB | PostgreSQL 16 |
| Vector DB | pgvector (same PostgreSQL instance) |
| Auth | bcrypt + JWT (httpOnly cookie), roles: Admin, Dispatcher, Reporter |
| Dev environment | Docker Compose |
| Version control | Git + GitHub |

**Database justification:** PostgreSQL holds structured, transactional data
(requests, resources, allocations) that needs ACID guarantees. pgvector holds
embeddings of free-text emergency descriptions for semantic duplicate
detection and similar-incident retrieval.

## Team and Work Split
Work is done in two sequential phases.

| Phase | Owner | Scope |
|---|---|---|
| 1 | <Name A> | Repo/env setup, ER diagram, relational schema, data dictionary, DDL (CREATE/ALTER/DROP, constraints), stored functions, allocation transaction, triggers, seed data, Next.js scaffold, DB connection, authentication and role guards, request-creation and allocation APIs |
| 2 | <Name B> | Indexes + EXPLAIN ANALYZE, views, full-text search, important queries (JOIN/GROUP BY/HAVING/subqueries), vector pipeline (embeddings, HNSW, duplicate detection), UI pages and dashboards, remaining API routes, test cases, screenshots, architecture diagram, final documentation, demo prep |

## Prerequisites (Windows)
Git, Node.js LTS (v20+), Docker Desktop (WSL 2 backend), VS Code.

## Quick Start
```powershell
git clone https://github.com/<user>/resqnet.git
cd resqnet
copy .env.example .env          # then edit values if you like
docker compose up -d            # starts PostgreSQL + pgvector, runs db/init/*.sql
# once the app/ folder exists:
cd app
copy .env.local.example .env.local
npm install
npm run dev                     # http://localhost:3000
```
Reset the database: `docker compose down -v` then `docker compose up -d`.

## Repository Layout
- `db/init/` SQL that runs automatically on first DB start
- `db/demo/` SQL run manually for demos (ALTER/DROP, queries, EXPLAIN, concurrency)
- `app/` Next.js application
- `docs/` ER diagram, schema, data dictionary, screenshots
- `tests/` test cases and results

## Project Status
**Phase 1 (<Name A>)**
- [x] Repo, folder structure, Docker environment
- [ ] Objectives and functional requirements
- [ ] ER diagram
- [ ] Relational schema and data dictionary
- [ ] DDL with constraints; ALTER/DROP demo
- [ ] Functions, allocation transaction, triggers
- [ ] Seed data
- [ ] Next.js scaffold, DB connection, auth and roles
- [ ] Request-creation and allocation APIs

**Phase 2 (<Name B>)**
- [ ] Indexes and EXPLAIN ANALYZE evidence
- [ ] Views
- [ ] Full-text search
- [ ] Important queries
- [ ] Vector embeddings and semantic search
- [ ] UI pages and dashboards
- [ ] Remaining API routes
- [ ] Tests, screenshots, final docs, demo prep

## Notes for <Name B> (Phase 2)
_Filled in at handoff: what's done, how to run it, test logins, known issues._

## Git Workflow
- `main` is stable. Work on `feat/<short-name>` branches and merge by pull request.
- Use your own git identity. Small, clear commits (`feat:`, `fix:`, `docs:`).
- Never commit `.env` or `.env.local`.