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
  const action = (p?.action ?? "").toString().trim();
  if (!admin_token) return json({ ok: false, error: "admin_token requis" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Auth admin
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  // 2. Routage par action.
  if (action === "mouvements") {
    const { data, error } = await supabase.rpc("journal_mouvements");
    if (error) return json({ ok: false, error: error.message || "Échec de la lecture des mouvements" }, 500);
    return json({ ok: true, admin: adminNom, mouvements: data ?? [] });
  }

  if (action === "archives") {
    const { data, error } = await supabase.rpc("journal_archives");
    if (error) return json({ ok: false, error: error.message || "Échec de la lecture des archives" }, 500);
    return json({ ok: true, admin: adminNom, archives: data ?? [] });
  }

  if (action === "cloturer") {
    const contenu = (p?.contenu ?? "").toString();
    if (!contenu.trim()) return json({ ok: false, error: "contenu requis (une archive vide n'a aucune valeur)" }, 400);
    // p_par = adminNom (nom vérifié serveur, jamais du body).
    const { data, error } = await supabase.rpc("journal_cloturer", { p_par: adminNom, p_contenu: contenu });
    if (error) return json({ ok: false, error: error.message || "Échec de la clôture du journal" }, 500);
    return json({ ok: true, admin: adminNom, id: data });
  }

  return json({ ok: false, error: "Action inconnue" }, 400);
});
