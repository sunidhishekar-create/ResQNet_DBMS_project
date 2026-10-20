import { requireRole } from "@/lib/auth";
import { withTransaction, parseId, errorResponse } from "@/lib/tx";

// Cancel a request that has no active allocations.
// Reporters may cancel their own; dispatchers and admins may cancel any.
export async function POST(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireRole("ADMIN", "DISPATCHER", "REPORTER");
  if (auth instanceof Response) return auth;
  const id = parseId((await params).id);
  if (!id) return Response.json({ error: "Invalid id" }, { status: 400 });

  try {
    const outcome = await withTransaction(auth.userId, async (c) => {
      const cur = await c.query(
        "SELECT requested_by, status FROM emergency_request WHERE request_id = $1 FOR UPDATE",
        [id]
      );
      const row = cur.rows[0];
      if (!row || (auth.role === "REPORTER" && row.requested_by !== auth.userId)) {
        return { code: 404, body: { error: "Request not found" } };
      }
      if (row.status !== "PENDING") {
        return {
          code: 409,
          body: { error: `Only PENDING requests can be cancelled (this one is ${row.status}). Release its allocations first.` },
        };
      }
      await c.query("UPDATE emergency_request SET status = 'CANCELLED' WHERE request_id = $1", [id]);
      return { code: 200, body: { request_id: id, status: "CANCELLED" } };
    });
    return Response.json(outcome.body, { status: outcome.code });
  } catch (err) {
    return errorResponse(err);
  }
}