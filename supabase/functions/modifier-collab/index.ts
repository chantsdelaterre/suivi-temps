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

const CHAMPS_AUTORISES = [
  "prenom", "nom", "nom_affiche", "email", "telephone",
  "statut", "actif", "date_activation", "matricule_silae", "equipe_id",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);

  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const admin_token = (p?.admin_token ?? "").toString().trim();
  const collab_id = (p?.collab_id ?? "").toString().trim();
  const champs = (p && typeof p.champs === "object" && p.champs) ? p.champs : {};

  if (!admin_token || !collab_id) return json({ ok: false, error: "admin_token et collab_id requis" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Auth admin via la RPC existante
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  // 2. Update limité à la whitelist
  const maj: Record<string, unknown> = {};
  for (const k of CHAMPS_AUTORISES) { if (k in champs) maj[k] = champs[k]; }
  if (Object.keys(maj).length === 0) return json({ ok: false, error: "Aucun champ modifiable fourni" }, 400);

  const { error: uErr } = await supabase.from("collaborateurs").update(maj).eq("collab_id", collab_id);
  if (uErr) return json({ ok: false, error: "Échec de l'enregistrement" }, 500);

  return json({ ok: true, admin: adminNom });
});
