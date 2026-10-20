import { z } from "zod";
import { requireRole } from "@/lib/auth";
import { withTransaction, parseId, errorResponse } from "@/lib/tx";

const schema = z.object({
  resource_id: z.number().int().positive(),
  qty: z.number().int().positive(),
});

// Atomic allocation: all the checking, locking and inserting happens inside
// the allocate_resource() database function; triggers update stock and status.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireRole("ADMIN", "DISPATCHER");
  if (auth instanceof Response) return auth;
  const id = parseId((await params).id);
  if (!id) return Response.json({ error: "Invalid id" }, { status: 400 });

  const parsed = schema.safeParse(await req.json().catch(() => null));
  if (!parsed.success) {
    return Response.json({ error: "resource_id and qty must be positive integers" }, { status: 400 });
  }

  try {
    const result = await withTransaction(auth.userId, async (c) => {
      const a = await c.query("SELECT allocate_resource($1, $2, $3, $4) AS allocation_id", [
        id, parsed.data.resource_id, parsed.data.qty, auth.userId,
      ]);
      const r = await c.query(
        `SELECT r.status, res.available_qty AS resource_available
           FROM emergency_request r, resource res
          WHERE r.request_id = $1 AND res.resource_id = $2`,
        [id, parsed.data.resource_id]
      );
      return { allocation_id: a.rows[0].allocation_id, ...r.rows[0] };
    });
    return Response.json(result);
  } catch (err) {
    return errorResponse(err);
  }
}