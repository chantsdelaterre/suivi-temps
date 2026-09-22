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

// Colonnes acceptées en écriture. Tout le reste du body est IGNORÉ :
// id, cree_le, modifie_le, modifie_par ne se posent jamais depuis le client.
const COLS_ECRITURE = [
  "mouvement", "type_contrat", "avec_suite", "objet", "tiers",
  "echeance_jours", "echeance_sens", "note", "ordre", "actif",
  "type_periode", "portee",
];

// Construit un objet ne contenant QUE les colonnes whitelistées présentes dans le body.
function filtrerColonnes(p: any): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of COLS_ECRITURE) {
    if (k in p) out[k] = p[k];
  }
  return out;
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
  if (action === "liste") {
    // Actives ET inactives (l'écran d'admin doit voir les deux).
    const { data, error } = await supabase
      .from("journal_regles")
      .select("*")
      .order("ordre", { ascending: true })
      .order("id", { ascending: true });
    if (error) return json({ ok: false, error: error.message || "Échec de la lecture des règles" }, 500);
    return json({ ok: true, admin: adminNom, regles: data ?? [] });
  }

  if (action === "creer") {
    // Whitelist stricte : les CHECK en base valident les listes fermées et remontent leur message.
    const payload = filtrerColonnes(p);
    const { data, error } = await supabase
      .from("journal_regles")
      .insert(payload)
      .select()
      .single();
    if (error) return json({ ok: false, error: error.message || "Échec de la création de la règle" }, 500);
    return json({ ok: true, admin: adminNom, regle: data });
  }

  if (action === "modifier") {
    const id = Number(p?.id);
    if (!Number.isInteger(id) || id <= 0) return json({ ok: false, error: "id requis" }, 400);
    // modifie_le / modifie_par posés serveur, JAMAIS depuis le body.
    const payload = { ...filtrerColonnes(p), modifie_le: new Date().toISOString(), modifie_par: adminNom };
    const { data, error } = await supabase
      .from("journal_regles")
      .update(payload)
      .eq("id", id)
      .select()
      .single();
    if (error) return json({ ok: false, error: error.message || "Échec de la modification de la règle" }, 500);
    return json({ ok: true, admin: adminNom, regle: data });
  }

  if (action === "supprimer") {
    const id = Number(p?.id);
    if (!Number.isInteger(id) || id <= 0) return json({ ok: false, error: "id requis" }, 400);
    const { error } = await supabase
      .from("journal_regles")
      .delete()
      .eq("id", id);
    if (error) return json({ ok: false, error: error.message || "Échec de la suppression de la règle" }, 500);
    return json({ ok: true, admin: adminNom, id });
  }

  return json({ ok: false, error: "Action inconnue" }, 400);
});
