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
  const periode_id = (p?.periode_id ?? "").toString().trim();
  if (!admin_token || !periode_id) return json({ ok: false, error: "admin_token et periode_id requis" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Auth admin
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  // 2. Invariant de transition : la période doit être 'gelee'
  const { data: periode, error: pErr } = await supabase
    .from("periodes").select("statut").eq("periode_id", periode_id).maybeSingle();
  if (pErr) return json({ ok: false, error: "Erreur base (periodes)" }, 500);
  if (!periode) return json({ ok: false, error: "Période introuvable" }, 404);
  if (periode.statut === "cloturee") return json({ ok: false, error: "Période déjà clôturée" }, 409);
  if (periode.statut !== "gelee") return json({ ok: false, error: "La période doit être gelée pour être clôturée" }, 403);

  // 3. Écriture
  const { error: uErr } = await supabase
    .from("periodes").update({ statut: "cloturee" }).eq("periode_id", periode_id);
  if (uErr) return json({ ok: false, error: "Échec de la clôture" }, 500);

  return json({ ok: true, admin: adminNom });
});
