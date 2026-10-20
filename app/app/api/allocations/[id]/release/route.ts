import { requireRole } from "@/lib/auth";
import { withTransaction, parseId, errorResponse } from "@/lib/tx";

// Release an active allocation: stock is restored and the request status
// is recalculated by database triggers.
export async function POST(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireRole("ADMIN", "DISPATCHER");
  if (auth instanceof Response) return auth;
  const id = parseId((await params).id);
  if (!id) return Response.json({ error: "Invalid id" }, { status: 400 });

  try {
    await withTransaction(auth.userId, (c) =>
      c.query("SELECT release_allocation($1, $2)", [id, auth.userId])
    );
    return Response.json({ allocation_id: id, status: "RELEASED" });
  } catch (err) {
    return errorResponse(err);
  }
}