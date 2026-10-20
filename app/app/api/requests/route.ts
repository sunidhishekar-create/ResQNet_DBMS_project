import { z } from "zod";
import { pool } from "@/lib/db";
import { requireRole } from "@/lib/auth";
import { withTransaction, errorResponse } from "@/lib/tx";

const createSchema = z.object({
  incident_id: z.number().int().positive(),
  type_id: z.number().int().positive(),
  qty_needed: z.number().int().positive().max(100000),
  severity: z.number().int().min(1).max(10),
  affected_people: z.number().int().min(0).max(1000000),
  description: z.string().trim().min(5, "Description must be at least 5 characters").max(2000),
});

// Any logged-in user can report an emergency
export async function POST(req: Request) {
  const auth = await requireRole("ADMIN", "DISPATCHER", "REPORTER");
  if (auth instanceof Response) return auth;

  const parsed = createSchema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return Response.json(
      { error: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ") },
      { status: 400 }
    );
  }
  const r = parsed.data;

  try {
    const created = await withTransaction(auth.userId, async (c) => {
      const ins = await c.query(
        `INSERT INTO emergency_request
                (incident_id, requested_by, type_id, qty_needed, severity, affected_people, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING request_id, status, created_at`,
        [r.incident_id, auth.userId, r.type_id, r.qty_needed, r.severity, r.affected_people, r.description]
      );
      const row = ins.rows[0];
      const score = await c.query("SELECT compute_priority_score($1) AS s", [row.request_id]);
      return { ...row, priority_score: Number(score.rows[0].s) };
    });
    return Response.json({ request: created }, { status: 201 });
  } catch (err) {
    return errorResponse(err);
  }
}

const listSchema = z.object({
  status: z.enum(["OPEN", "ALL", "PENDING", "PARTIAL", "FULFILLED", "CANCELLED"]).optional(),
  disaster_id: z.coerce.number().int().positive().optional(),
  type_id: z.coerce.number().int().positive().optional(),
  min_severity: z.coerce.number().int().min(1).max(10).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

// Prioritised queue. Dispatchers/admins see everyone's requests (default: open ones);
// reporters only ever see their own.
export async function GET(req: Request) {
  const auth = await requireRole("ADMIN", "DISPATCHER", "REPORTER");
  if (auth instanceof Response) return auth;

  const parsed = listSchema.safeParse(Object.fromEntries(new URL(req.url).searchParams));
  if (!parsed.success) {
    return Response.json({ error: "Invalid query parameters" }, { status: 400 });
  }
  const q = parsed.data;
  const status = q.status ?? (auth.role === "REPORTER" ? "ALL" : "OPEN");

  const where: string[] = [];
  const params: unknown[] = [];
  const add = (sql: string, value: unknown) => {
    params.push(value);
    where.push(sql.replace("?", `$${params.length}`));
  };

  if (auth.role === "REPORTER") add("r.requested_by = ?", auth.userId);
  if (status === "OPEN") where.push("r.status IN ('PENDING', 'PARTIAL')");
  else if (status !== "ALL") add("r.status = ?", status);
  if (q.disaster_id) add("d.disaster_id = ?", q.disaster_id);
  if (q.type_id) add("r.type_id = ?", q.type_id);
  if (q.min_severity) add("r.severity >= ?", q.min_severity);

  params.push(q.limit, q.offset);
  const sql = `
    SELECT r.request_id, r.status, r.severity, r.affected_people, r.qty_needed,
           r.description, r.created_at,
           rt.name AS resource_type, d.name AS disaster, l.name AS location, l.district,
           compute_priority_score(r.request_id) AS priority_score,
           COALESCE((SELECT SUM(a.qty_allocated) FROM resource_allocation a
                      WHERE a.request_id = r.request_id AND a.status = 'ACTIVE'), 0)::int AS qty_allocated
      FROM emergency_request r
      JOIN resource_type rt ON rt.type_id = r.type_id
      JOIN incident i       ON i.incident_id = r.incident_id
      JOIN disaster d       ON d.disaster_id = i.disaster_id
      JOIN location l       ON l.location_id = i.location_id
     ${where.length ? "WHERE " + where.join(" AND ") : ""}
     ORDER BY priority_score DESC, r.created_at ASC
     LIMIT $${params.length - 1} OFFSET $${params.length}`;

  try {
    const { rows } = await pool.query(sql, params);
    return Response.json({
      requests: rows.map((x) => ({ ...x, priority_score: Number(x.priority_score) })),
      count: rows.length,
    });
  } catch (err) {
    return errorResponse(err);
  }
}