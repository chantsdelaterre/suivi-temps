import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);

  let payload;
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: "JSON invalide" }, 400);
  }

  const jour_id = (payload?.jour_id ?? "").toString().trim();
  const manager_token = (payload?.manager_token ?? "").toString().trim();
  const remarque = (payload?.remarque ?? "").toString();

  if (!jour_id || !manager_token) {
    return json({ ok: false, error: "jour_id et manager_token requis" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Authentifier le manager via son token
  const { data: equipe, error: eqErr } = await supabase
    .from("equipes")
    .select("equipe_id, actif")
    .eq("manager_token", manager_token)
    .maybeSingle();
  if (eqErr) return json({ ok: false, error: "Erreur base (equipes)" }, 500);
  if (!equipe || equipe.actif === false) {
    return json({ ok: false, error: "Token manager invalide" }, 401);
  }

  // 2. Retrouver le collaborateur du jour visé
  const { data: jour, error: jErr } = await supabase
    .from("jours")
    .select("collab_id")
    .eq("jour_id", jour_id)
    .maybeSingle();
  if (jErr) return json({ ok: false, error: "Erreur base (jours)" }, 500);
  if (!jour) return json({ ok: false, error: "Jour introuvable" }, 404);

  // 3. Verifier que ce collaborateur appartient a l'equipe du manager
  const { data: collab, error: cErr } = await supabase
    .from("collaborateurs")
    .select("equipe_id")
    .eq("collab_id", jour.collab_id)
    .maybeSingle();
  if (cErr) return json({ ok: false, error: "Erreur base (collaborateurs)" }, 500);
  if (!collab || collab.equipe_id !== equipe.equipe_id) {
    return json({ ok: false, error: "Ce jour n'appartient pas a votre equipe" }, 403);
  }

  // 4. Ecriture de la remarque
  const { error: uErr } = await supabase
    .from("jours")
    .update({ remarque_manager: remarque })
    .eq("jour_id", jour_id);
  if (uErr) return json({ ok: false, error: "Echec de l'enregistrement" }, 500);

  return json({ ok: true });
});
