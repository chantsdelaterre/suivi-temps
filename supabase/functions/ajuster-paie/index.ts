import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);
  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const admin_token = (p?.admin_token ?? "").toString().trim();
  const updates = Array.isArray(p?.updates) ? p.updates : null;
  if (!admin_token || !updates || updates.length === 0) return json({ ok: false, error: "admin_token et updates requis" }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  const CREN_COLS = ["c1_debut_valide","c1_fin_valide","c2_debut_valide","c2_fin_valide","c3_debut_valide","c3_fin_valide"];
  for (const u of updates) {
    if (u?.id == null) return json({ ok: false, error: "id manquant dans une ligne" }, 400);
    const maj: Record<string, unknown> = {
      type_jour_valide: u.type_jour_valide,
      heures_valide: u.heures_valide,
      ajuste_admin: true,
    };
    for (const col of CREN_COLS) if (u[col] !== undefined) maj[col] = u[col];
    const { error: uErr } = await supabase.from("paie_detail").update(maj).eq("id", u.id);
    if (uErr) return json({ ok: false, error: "Échec ajustement (id " + u.id + ")" }, 500);
  }
  return json({ ok: true, n: updates.length });
});
