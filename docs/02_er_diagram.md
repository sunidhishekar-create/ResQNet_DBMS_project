# ER Diagram

```mermaid
erDiagram
    USERS ||--o{ EMERGENCY_REQUEST : submits
    USERS ||--o{ RESOURCE_ALLOCATION : performs
    USERS ||--o{ AUDIT_LOG : causes
    DISASTER ||--o{ INCIDENT : has
    LOCATION ||--o{ INCIDENT : occurs_at
    LOCATION ||--o{ RESOURCE : stationed_at
    RESOURCE_TYPE ||--o{ RESOURCE : classifies
    RESOURCE_TYPE ||--o{ EMERGENCY_REQUEST : requested_as
    INCIDENT ||--o{ EMERGENCY_REQUEST : generates
    EMERGENCY_REQUEST ||--o{ RESOURCE_ALLOCATION : served_by
    RESOURCE ||--o{ RESOURCE_ALLOCATION : used_in
    EMERGENCY_REQUEST ||--o| REQUEST_EMBEDDING : has

    USERS {
        int user_id PK
        string full_name
        string email UK
        string password_hash
        string role
        timestamp created_at
    }
    DISASTER {
        int disaster_id PK
        string name
        string disaster_type
        string status
        date start_date
        date end_date
    }
    LOCATION {
        int location_id PK
        string name
        string district
        decimal latitude
        decimal longitude
    }
    INCIDENT {
        int incident_id PK
        int disaster_id FK
        int location_id FK
        string description
        string status
        timestamp reported_at
    }
    RESOURCE_TYPE {
        int type_id PK
        string name UK
        string category
        string unit
        int urgency_weight
    }
    RESOURCE {
        int resource_id PK
        int type_id FK
        int location_id FK
        string name
        int total_qty
        int available_qty
        string status
    }
    EMERGENCY_REQUEST {
        int request_id PK
        int incident_id FK
        int requested_by FK
        int type_id FK
        int qty_needed
        int severity
        int affected_people
        string description
        string status
        timestamp created_at
        timestamp fulfilled_at
    }
    RESOURCE_ALLOCATION {
        int allocation_id PK
        int request_id FK
        int resource_id FK
        int allocated_by FK
        int qty_allocated
        decimal distance_km
        decimal priority_score
        string status
        timestamp allocated_at
        timestamp released_at
    }
    AUDIT_LOG {
        bigint log_id PK
        string table_name
        int record_id
        string action
        string old_value
        string new_value
        int changed_by FK
        timestamp changed_at
    }
    REQUEST_EMBEDDING {
        int request_id PK
        string embedding
        string model_name
        timestamp created_at
    }
```

## Key design points

- **EMERGENCY_REQUEST and RESOURCE are M:N**, resolved by RESOURCE_ALLOCATION, which carries its own attributes (quantity, distance, score, status, timestamps).
- **Priority score** (severity, affected people, resource urgency weight, waiting time) belongs to the request. **Match score** (distance, availability) belongs to a request-resource pair, so distance lives on the allocation.
- **REQUEST_EMBEDDING** is a 1:1 optional child of the request (its `request_id` is both PK and FK), with `ON DELETE CASCADE`. The `embedding` column is a pgvector `vector(384)`, shown as text here because Mermaid has no vector type.
- **AUDIT_LOG** deliberately has no FK to the audited tables, so history survives deletions. `old_value` and `new_value` are JSONB in the real schema.