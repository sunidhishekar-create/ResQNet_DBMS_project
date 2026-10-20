import { pool } from "@/lib/db";
import { requireRole } from "@/lib/auth";
import { parseId, errorResponse } from "@/lib/tx";

// Request detail with its allocations. Reporters can only open their own.
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireRole("ADMIN", "DISPATCHER", "REPORTER");
  if (auth instanceof Response) return auth;
  const id = parseId((await params).id);
  if (!id) return Response.json({ error: "Invalid id" }, { status: 400 });

  try {
    const { rows } = await pool.query(
      `SELECT r.*, rt.name AS resource_type, d.name AS disaster, l.name AS location,
              l.district, u.full_name AS reporter,
              compute_priority_score(r.request_id) AS priority_score
         FROM emergency_request r
         JOIN resource_type rt ON rt.type_id = r.type_id
         JOIN incident i ON i.incident_id = r.incident_id
         JOIN disaster d ON d.disaster_id = i.disaster_id
         JOIN location l ON l.location_id = i.location_id
         JOIN users u ON u.user_id = r.requested_by
        WHERE r.request_id = $1`,
      [id]
    );
    const row = rows[0];
    if (!row || (auth.role === "REPORTER" && row.requested_by !== auth.userId)) {
      return Response.json({ error: "Request not found" }, { status: 404 });
    }
    const allocs = await pool.query(
      `SELECT a.allocation_id, a.qty_allocated, a.distance_km, a.priority_score, a.status,
              a.allocated_at, a.released_at, res.name AS resource, u.full_name AS allocated_by
         FROM resource_allocation a
         JOIN resource res ON res.resource_id = a.resource_id
         JOIN users u ON u.user_id = a.allocated_by
        WHERE a.request_id = $1
        ORDER BY a.allocated_at`,
      [id]
    );
    return Response.json({
      request: { ...row, priority_score: Number(row.priority_score) },
      allocations: allocs.rows,
    });
  } catch (err) {
    return errorResponse(err);
  }
}