# Objectives and Functional Requirements

## Objectives
1. Match limited emergency resources to constantly changing emergency requests
   using severity, affected people, distance, resource urgency, waiting time
   and availability.
2. Guarantee that a resource is never over-allocated, even when several
   dispatchers act at once (ACID transactions).
3. Detect duplicate or similar emergency reports using semantic search
   (pgvector).
4. Give each role (Admin, Dispatcher, Reporter) only the access it needs.
5. Keep a full audit trail of changes to requests, resources and allocations.

## Roles
| Role | Can do |
|---|---|
| Reporter | Submit emergency requests, view own requests and their status |
| Dispatcher | View the prioritised queue, allocate/release resources, update request status |
| Admin | Everything above, plus manage users, disasters, locations, resource types, resources; view analytics and audit log |

## Functional Requirements
| ID | Requirement |
|---|---|
| FR1 | Users register and log in; passwords are hashed; sessions use JWT |
| FR2 | Reporter submits a request: incident, resource type, quantity, severity (1-10), affected people, description |
| FR3 | System computes a priority score per request and lists pending requests in priority order |
| FR4 | System ranks candidate resources for a request (distance, availability, type match) |
| FR5 | Dispatcher allocates a resource to a request (full or partial) in one atomic transaction |
| FR6 | Allocation decrements available quantity; release restores it (trigger) |
| FR7 | A request becomes PARTIAL or FULFILLED automatically as allocations accumulate |
| FR8 | Every change to requests, resources and allocations is written to the audit log (trigger) |
| FR9 | Admin manages disasters, incidents, locations, resource types, resources, users |
| FR10 | Search requests by keyword (full-text) and by meaning (semantic) |
| FR11 | New requests are checked against existing ones and likely duplicates are flagged |
| FR12 | Dashboard shows pending/fulfilled counts, utilisation per resource type, per-disaster summary |
| FR13 | Database rejects invalid data (bad severity, negative quantity, over-allocation, duplicate email) |