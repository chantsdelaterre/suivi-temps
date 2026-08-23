import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);

  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const admin_token = (p?.admin_token ?? "").toString().trim();
  const ids = Array.isArray(p?.ids) ? p.ids.map((x: unknown) => Number(x)) : [];
  const date_debut = (p?.date_debut ?? "").toString().trim();
  const date_fin = (p?.date_fin ?? "").toString().trim();

  if (!admin_token || !ids.length || !date_debut || !date_fin) {
    return json({ ok: false, error: "admin_token, ids, date_debut, date_fin requis" }, 400);
  }
  if (ids.some((n: number) => !Number.isFinite(n))) {
    return json({ ok: false, error: "ids invalide" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Auth admin
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  // 2. RPC transactionnelle (tout ou rien). p_par = adminNom (nom vérifié serveur, jamais du body).
  //    ⚠️ Le message d'erreur RPC nomme le collaborateur en cause : transmis TEL QUEL à l'admin.
  const { data: rData, error: rErr } = await supabase.rpc("renouveler_contrats_lot", {
    p_ids: ids,
    p_date_debut: date_debut,
    p_date_fin: date_fin,
    p_par: adminNom,
  });
  if (rErr) return json({ ok: false, error: rErr.message || "Échec du renouvellement en lot" }, 500);

  return json({ ok: true, admin: adminNom, crees: rData });
});
