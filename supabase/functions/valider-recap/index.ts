import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const COLS = [
  "periode_id","collab_id","nom_affiche","heures_travaillees","heures_at","heures_cs",
  "nb_at","nb_cs","nb_cp","nb_jours_travailles","statut_validation","date_validation","note_admin",
  "date_fin_validation",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);
  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const admin_token = (p?.admin_token ?? "").toString().trim();
  const recap = (p?.recap && typeof p.recap === "object") ? p.recap : null;
  if (!admin_token || !recap) return json({ ok: false, error: "admin_token et recap requis" }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  const row: Record<string, unknown> = {};
  for (const k of COLS) if (k in recap) row[k] = recap[k];
  if (!row.periode_id || !row.collab_id) return json({ ok: false, error: "periode_id et collab_id requis" }, 400);

  const { error: uErr } = await supabase.from("recap_paie").upsert(row, { onConflict: "periode_id,collab_id" });
  if (uErr) return json({ ok: false, error: uErr.message || "Échec de la validation" }, 500);
  return json({ ok: true });
});
