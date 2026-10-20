import { pool } from "@/lib/db";
import { requireRole } from "@/lib/auth";

// Lookup data for forms: incidents (with disaster and place) and resource types
export async function GET() {
  const auth = await requireRole("ADMIN", "DISPATCHER", "REPORTER");
  if (auth instanceof Response) return auth;

  const [incidents, types] = await Promise.all([
    pool.query(
      `SELECT i.incident_id, i.description, i.status,
              d.disaster_id, d.name AS disaster, l.name AS location, l.district
         FROM incident i
         JOIN disaster d ON d.disaster_id = i.disaster_id
         JOIN location l ON l.location_id = i.location_id
        WHERE i.status <> 'RESOLVED' AND d.status <> 'CLOSED'
        ORDER BY d.name, l.name`
    ),
    pool.query("SELECT type_id, name, category, unit FROM resource_type ORDER BY category, name"),
  ]);
  return Response.json({ incidents: incidents.rows, resource_types: types.rows });
}