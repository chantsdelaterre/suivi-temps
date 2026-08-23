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

  const manager_token = (p?.manager_token ?? "").toString().trim();
  if (!manager_token) return json({ ok: false, error: "manager_token requis" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // Auth + données en UN seul appel : la RPC vérifie le token MANAGER (pas de verifier_admin ici).
  const { data, error } = await supabase.rpc("manager_equipe", { p_manager_token: manager_token });
  if (error) return json({ ok: false, error: error.message || "Erreur base (manager_equipe)" }, 500);

  // La vérification du token vit DANS la RPC : ok:false → accès refusé (401).
  if (!data || data.ok !== true) return json({ ok: false, error: "Accès refusé" }, 401);

  return json({ ok: true, equipe: data.equipe, membres: data.membres, jours: data.jours });
});
