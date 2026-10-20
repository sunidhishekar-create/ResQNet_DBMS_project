import { pool } from "@/lib/db";
import { requireRole } from "@/lib/auth";
import { parseId, errorResponse } from "@/lib/tx";

// Ranked resources that could serve this request (distance + stock match score)
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireRole("ADMIN", "DISPATCHER");
  if (auth instanceof Response) return auth;
  const id = parseId((await params).id);
  if (!id) return Response.json({ error: "Invalid id" }, { status: 400 });

  try {
    const { rows } = await pool.query("SELECT * FROM rank_candidate_resources($1)", [id]);
    return Response.json({
      candidates: rows.map((c) => ({
        ...c,
        distance_km: Number(c.distance_km),
        match_score: Number(c.match_score),
      })),
    });
  } catch (err) {
    return errorResponse(err);
  }
}