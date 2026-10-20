   import { pool } from "@/lib/db";

   export async function GET() {
     const { rows } = await pool.query(
       "SELECT count(*)::int AS requests FROM emergency_request"
     );
     return Response.json({ ok: true, requests: rows[0].requests });
   }