// =====================================================================
// ResQNet: tests/phase1_api_tests.mjs
// End-to-end API test cases (auth, roles, validation, queue, allocation,
// release, cancel, concurrency). Needs Node 18+ (built-in fetch).
//
// Run (app must be running with `npm run dev`, database seeded):
//     node tests/phase1_api_tests.mjs
// Optional:  BASE_URL=http://localhost:3000 node tests/phase1_api_tests.mjs
//
// The script is safe to re-run: it creates its own requests, and releases or
// cancels everything it creates, so stock levels return to what they were.
// =====================================================================

const BASE = process.env.BASE_URL ?? "http://localhost:3000";
const PASSWORD = "Demo@1234";

class Client {
  constructor() { this.cookie = ""; }
  async req(method, path, body) {
    const res = await fetch(BASE + path, {
      method,
      headers: {
        ...(body ? { "Content-Type": "application/json" } : {}),
        ...(this.cookie ? { Cookie: this.cookie } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      redirect: "manual",
    });
    const setCookies = res.headers.getSetCookie?.() ?? [];
    for (const c of setCookies) {
      const [pair] = c.split(";");
      const idx = pair.indexOf("=");
      const name = pair.slice(0, idx);
      const val = pair.slice(idx + 1);
      this.cookie = val === "" ? "" : `${name}=${val}`;
    }
    let data = null;
    try { data = await res.json(); } catch { /* no body */ }
    return { status: res.status, data, setCookies };
  }
  get(p) { return this.req("GET", p); }
  post(p, b) { return this.req("POST", p, b); }
  async login(email, password = PASSWORD) {
    return this.post("/api/auth/login", { email, password });
  }
}

const results = [];
function check(_ignored, name, expected, ok, actual) {
  const id = "A" + String(results.length + 1).padStart(2, "0");
  results.push({ id, name, expected, ok, actual });
  console.log(`${ok ? "PASS" : "FAIL"}  ${id}  ${name}  (expected ${expected}, got ${actual})`);
}

async function main() {
  const anon = new Client();
  const admin = new Client();
  const dsp1 = new Client();
  const dsp2 = new Client();
  const rep1 = new Client();
  const rep2 = new Client();

  // ---------------- Auth ----------------
  let r = await anon.get("/api/health");
  check("A01", "Health check reaches the database", "200 ok", r.status === 200 && r.data?.ok === true, r.status);

  r = await anon.get("/api/admin/users");
  check("A02", "Protected route without login", "401", r.status === 401, r.status);

  r = await anon.login("admin@resqnet.test", "wrong-password");
  check("A03", "Login with wrong password", "401", r.status === 401, r.status);

  r = await admin.login("admin@resqnet.test");
  const flags = (r.setCookies[0] ?? "").toLowerCase();
  check("A04", "Admin login sets an httpOnly session cookie", "200 + HttpOnly",
        r.status === 200 && r.data?.user?.role === "ADMIN" && flags.includes("httponly"),
        `${r.status} ${flags.includes("httponly") ? "HttpOnly" : "no HttpOnly"}`);

  r = await admin.get("/api/admin/users");
  check("A05", "Admin lists users", "200, 6+ users", r.status === 200 && r.data?.users?.length >= 6,
        `${r.status}, ${r.data?.users?.length} users`);

  await dsp1.login("dispatcher1@resqnet.test");
  await dsp2.login("dispatcher2@resqnet.test");
  await rep1.login("reporter1@resqnet.test");
  await rep2.login("reporter2@resqnet.test");

  r = await rep1.get("/api/admin/users");
  check("A06", "Reporter calls admin-only route", "403", r.status === 403, r.status);

  r = await dsp1.get("/api/admin/users");
  check("A07", "Dispatcher calls admin-only route", "403", r.status === 403, r.status);

  r = await anon.post("/api/auth/register", { full_name: "Dup", email: "admin@resqnet.test", password: "longenough1" });
  check("A08", "Register with an existing email (UNIQUE constraint)", "409", r.status === 409, r.status);

  r = await anon.post("/api/auth/register", { full_name: "Short", email: "short@example.com", password: "abc" });
  check("A09", "Register with a short password", "400", r.status === 400, r.status);

  const fresh = new Client();
  r = await fresh.post("/api/auth/register", {
    full_name: "QA Tester", email: `qa+${Date.now()}@example.com`, password: "longenough1",
  });
  check("A10", "Public registration creates a REPORTER only", "201 REPORTER",
        r.status === 201 && r.data?.user?.role === "REPORTER", `${r.status} ${r.data?.user?.role}`);

  const forged = new Client();
  forged.cookie = "resqnet_session=abc.def.ghi";
  r = await forged.get("/api/auth/me");
  check("A11", "Forged session cookie", "401", r.status === 401, r.status);

  r = await fresh.post("/api/auth/logout");
  check("A12", "Logout clears the cookie", "200 + cookie cleared", r.status === 200 && fresh.cookie === "",
        `${r.status}, cookie ${fresh.cookie === "" ? "cleared" : "still set"}`);

  // ---------------- Lookups and validation ----------------
  r = await rep1.get("/api/meta");
  const incidents = r.data?.incidents ?? [];
  const types = r.data?.resource_types ?? [];
  check("A13", "Lookup data for forms", "200, incidents + types", r.status === 200 && incidents.length > 0 && types.length > 0,
        `${r.status}, ${incidents.length} incidents, ${types.length} types`);

  const incidentId = incidents[0].incident_id;
  const ambulance = types.find((t) => t.name === "Ambulance") ?? types[0];
  const base = { incident_id: incidentId, type_id: ambulance.type_id, qty_needed: 1, severity: 10, affected_people: 3,
                 description: "QA test: two people hurt, ambulance needed urgently" };

  r = await rep1.post("/api/requests", { ...base, severity: 11 });
  check("A14", "Create request with severity 11", "400", r.status === 400, r.status);

  r = await rep1.post("/api/requests", { ...base, incident_id: 999999 });
  check("A15", "Create request with unknown incident (FK)", "400", r.status === 400, r.status);

  r = await rep1.post("/api/requests", { ...base, description: "abc" });
  check("A16", "Create request with too short description", "400", r.status === 400, r.status);

  // ---------------- Create, queue, filters ----------------
  r = await rep1.post("/api/requests", base);
  const mainId = r.data?.request?.request_id;
  check("A17", "Reporter creates a request", "201 PENDING + score",
        r.status === 201 && r.data?.request?.status === "PENDING" && r.data?.request?.priority_score > 0,
        `${r.status} ${r.data?.request?.status} score ${r.data?.request?.priority_score}`);

  r = await rep2.get("/api/requests?status=ALL&limit=200");
  const rep2Ids = (r.data?.requests ?? []).map((x) => x.request_id);
  check("A18", "A reporter cannot see another reporter's request in the list", "id absent",
        r.status === 200 && !rep2Ids.includes(mainId), `${r.status}, ${rep2Ids.includes(mainId) ? "visible" : "absent"}`);

  r = await rep2.get(`/api/requests/${mainId}`);
  check("A19", "A reporter opens another reporter's request", "404", r.status === 404, r.status);

  r = await dsp1.get("/api/requests?limit=200");
  const scores = (r.data?.requests ?? []).map((x) => x.priority_score);
  const sorted = scores.every((s, i) => i === 0 || scores[i - 1] >= s);
  check("A20", "Dispatcher queue is ordered by priority score", "descending", r.status === 200 && scores.length > 0 && sorted,
        `${scores.length} rows, ${sorted ? "descending" : "NOT sorted"}`);

  r = await dsp1.get("/api/requests?min_severity=10&limit=200");
  const allSev10 = (r.data?.requests ?? []).every((x) => x.severity >= 10);
  check("A21", "Filter min_severity=10", "all severity >= 10", r.status === 200 && allSev10, `${r.status}, ${r.data?.count} rows`);

  r = await dsp1.get("/api/requests?status=BOGUS");
  check("A22", "Invalid filter value", "400", r.status === 400, r.status);

  // ---------------- Candidates and allocation ----------------
  r = await rep1.get(`/api/requests/${mainId}/candidates`);
  check("A23", "Reporter asks for candidate resources", "403", r.status === 403, r.status);

  r = await dsp1.get(`/api/requests/${mainId}/candidates`);
  const cands = r.data?.candidates ?? [];
  const candSorted = cands.every((c, i) => i === 0 || cands[i - 1].match_score >= c.match_score);
  check("A24", "Candidates ranked by match score", "descending", r.status === 200 && cands.length > 0 && candSorted,
        `${cands.length} candidates, ${candSorted ? "descending" : "NOT sorted"}`);
  const top = cands[0];

  r = await rep1.post(`/api/requests/${mainId}/allocate`, { resource_id: top.resource_id, qty: 1 });
  check("A25", "Reporter tries to allocate", "403", r.status === 403, r.status);

  r = await dsp1.post(`/api/requests/${mainId}/allocate`, { resource_id: top.resource_id, qty: top.available_qty + 1 });
  check("A", "Allocate more than the available stock", "409 Insufficient stock",
        r.status === 409 && /Insufficient stock/.test(r.data?.error ?? ""), `${r.status} ${r.data?.error ?? ""}`);

  if (top.available_qty >= 2) {
    r = await dsp1.post(`/api/requests/${mainId}/allocate`, { resource_id: top.resource_id, qty: 2 });
    check("A", "Allocate more than the request needs (needs 1, ask 2)", "409 Over-allocation",
          r.status === 409 && /Over-allocation/.test(r.data?.error ?? ""), `${r.status} ${r.data?.error ?? ""}`);
  }

  r = await dsp1.post(`/api/requests/${mainId}/allocate`, { resource_id: top.resource_id, qty: 1 });
  const allocId = r.data?.allocation_id;
  check("A26", "Dispatcher allocates the top candidate", "200 FULFILLED, stock - 1",
        r.status === 200 && r.data?.status === "FULFILLED" && r.data?.resource_available === top.available_qty - 1,
        `${r.status} ${r.data?.status}, stock ${top.available_qty} -> ${r.data?.resource_available}`);

  r = await dsp1.post(`/api/requests/${mainId}/allocate`, { resource_id: top.resource_id, qty: 1 });
  check("A27", "Allocate to an already fulfilled request", "409", r.status === 409, `${r.status} ${r.data?.error ?? ""}`);

  r = await dsp1.get(`/api/requests/${mainId}`);
  const active = (r.data?.allocations ?? []).filter((a) => a.status === "ACTIVE").length;
  check("A29", "Request detail shows the active allocation and stamps fulfilled_at", "1 ACTIVE + fulfilled_at",
        active === 1 && !!r.data?.request?.fulfilled_at, `${active} ACTIVE, fulfilled_at ${r.data?.request?.fulfilled_at ? "set" : "null"}`);

  r = await dsp1.post(`/api/allocations/${allocId}/release`);
  check("A30", "Release the allocation", "200 RELEASED", r.status === 200 && r.data?.status === "RELEASED", r.status);

  r = await dsp1.get(`/api/requests/${mainId}`);
  check("A31", "Release reopens the request (trigger)", "PENDING, fulfilled_at null",
        r.data?.request?.status === "PENDING" && !r.data?.request?.fulfilled_at,
        `${r.data?.request?.status}, fulfilled_at ${r.data?.request?.fulfilled_at ? "set" : "null"}`);

  r = await dsp1.post(`/api/allocations/${allocId}/release`);
  check("A32", "Release the same allocation twice", "409", r.status === 409, `${r.status} ${r.data?.error ?? ""}`);

  // ---------------- Cancel ----------------
  r = await rep2.post(`/api/requests/${mainId}/cancel`);
  check("A33", "Reporter cancels someone else's request", "404", r.status === 404, r.status);

  r = await rep1.post(`/api/requests/${mainId}/cancel`);
  check("A34", "Reporter cancels own pending request", "200 CANCELLED", r.status === 200 && r.data?.status === "CANCELLED", r.status);

  r = await rep1.post(`/api/requests/${mainId}/cancel`);
  check("A35", "Cancel an already cancelled request", "409", r.status === 409, r.status);

  // ---------------- Concurrency ----------------
  // Two dispatchers each try to take ALL remaining stock of the same resource
  // for two different requests at the same instant. Exactly one may succeed.
  const stock = top.available_qty;
  const mk = async (c) => (await c.post("/api/requests", { ...base, qty_needed: stock })).data?.request?.request_id;
  const [idA, idB] = [await mk(rep1), await mk(rep2)];
  // Re-read stock: it is back to the original after the release above
  const [ra, rb] = await Promise.all([
    dsp1.post(`/api/requests/${idA}/allocate`, { resource_id: top.resource_id, qty: stock }),
    dsp2.post(`/api/requests/${idB}/allocate`, { resource_id: top.resource_id, qty: stock }),
  ]);
  const codes = [ra.status, rb.status].sort();
  check("A36", "Concurrent allocation of the same stock by two dispatchers", "one 200 and one 409",
        codes[0] === 200 && codes[1] === 409, `${ra.status} and ${rb.status}`);

  // Clean up: release the winner, cancel both requests
  for (const [resp, id] of [[ra, idA], [rb, idB]]) {
    if (resp.status === 200) await dsp1.post(`/api/allocations/${resp.data.allocation_id}/release`);
    await admin.post(`/api/requests/${id}/cancel`);
  }
  r = await dsp1.get(`/api/requests/${mainId}/candidates`);
  const after = (r.data?.candidates ?? []).find((c) => c.resource_id === top.resource_id);
  check("A37", "Stock is back to its original level after cleanup", `${stock}`, after?.available_qty === stock,
        `${after?.available_qty}`);

  const failed = results.filter((x) => !x.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });