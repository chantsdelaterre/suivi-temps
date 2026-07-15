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
  "periode_id","collab_id","date_jour","jour_semaine","type_jour",
  "c1_debut","c1_fin","c2_debut","c2_fin","c3_debut","c3_fin",
  "total_heures","commentaire","remarque_manager","total_hebdo_prog",
  "nb_modifications","date_derniere_modif","date_cloture",
  "type_jour_valide","heures_valide","ajuste_admin","note_admin",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);
  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const admin_token = (p?.admin_token ?? "").toString().trim();
  const lignes = Array.isArray(p?.lignes) ? p.lignes : null;
  if (!admin_token || !lignes || lignes.length === 0) return json({ ok: false, error: "admin_token et lignes requis" }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  const periode_id = (lignes[0]?.periode_id ?? "").toString();
  // Idempotence : si déjà importé, on ne réécrit rien
  const { count, error: cErr } = await supabase.from("paie_detail").select("id", { count: "exact", head: true }).eq("periode_id", periode_id);
  if (cErr) return json({ ok: false, error: "Erreur base (comptage)" }, 500);
  if ((count ?? 0) > 0) return json({ ok: true, importe: false, message: "déjà importé" });

  const rows = lignes.map((l: any) => { const r: Record<string, unknown> = {}; for (const k of COLS) if (k in l) r[k] = l[k]; return r; });
  const { error: iErr } = await supabase.from("paie_detail").insert(rows);
  if (iErr) return json({ ok: false, error: iErr.message || "Échec de l'import" }, 500);
  return json({ ok: true, importe: true, n: rows.length });
});
