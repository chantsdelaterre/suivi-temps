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

  const token = (p?.token ?? "").toString().trim();
  if (!token) return json({ ok: false, error: "token requis" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Auth + identité en UN appel : la RPC vérifie le token COLLABORATEUR (filtre actif=true inclus).
  // PAS de verifier_admin ici : c'est le token collab qui identifie.
  const { data, error } = await supabase.rpc("collab_session", { p_token: token });
  if (error) return json({ ok: false, error: error.message || "Erreur base (collab_session)" }, 500);

  // La vérification vit DANS la RPC : ok:false (lien_invalide) → 401, code d'erreur transmis tel quel.
  if (!data || data.ok !== true) return json({ ok: false, error: (data && data.error) || "lien_invalide" }, 401);

  return json({ ok: true, collab: data.collab });
});
