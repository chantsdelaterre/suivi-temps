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

function genToken(): string {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  const buf = new Uint8Array(14);
  crypto.getRandomValues(buf);
  let t = "";
  for (const b of buf) t += chars[b % chars.length];
  return t;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);

  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const admin_token = (p?.admin_token ?? "").toString().trim();
  const champs = (p?.champs && typeof p.champs === "object") ? p.champs : null;
  if (!admin_token || !champs) return json({ ok: false, error: "admin_token et champs requis" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Auth admin
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  // 2. Générer collab_id = COLL + (max existant + 1) sur 3 chiffres
  const { data: existants, error: eList } = await supabase.from("collaborateurs").select("collab_id");
  if (eList) return json({ ok: false, error: "Erreur base (liste collab)" }, 500);
  let maxNum = 0;
  for (const r of existants ?? []) {
    const m = /^COLL(\d+)$/.exec(r.collab_id || "");
    if (m) maxNum = Math.max(maxNum, parseInt(m[1], 10));
  }
  const collab_id = "COLL" + String(maxNum + 1).padStart(3, "0");

  // 3. Token unique
  let token = "";
  for (let i = 0; i < 20 && !token; i++) {
    const t = genToken();
    const { data: dup, error: eDup } = await supabase.from("collaborateurs").select("collab_id").eq("token", t).maybeSingle();
    if (eDup) return json({ ok: false, error: "Erreur base (verif token)" }, 500);
    if (!dup) token = t;
  }
  if (!token) return json({ ok: false, error: "Impossible de générer un token unique" }, 500);

  // 4. Création transactionnelle via la RPC existante
  const { error: rErr } = await supabase.rpc("creer_collaborateur_avec_contrat", {
    p_collab_id: collab_id,
    p_token: token,
    p_prenom: champs.prenom ?? null,
    p_nom: champs.nom ?? null,
    p_nom_affiche: champs.nom_affiche ?? null,
    p_email: champs.email ?? null,
    p_structure: champs.structure ?? null,
    p_equipe_id: champs.equipe_id ?? null,
    p_type_contrat: champs.type_contrat ?? null,
    p_type_periode: champs.type_periode ?? null,
    p_heures_hebdo: champs.heures_hebdo ?? null,
    p_statut: champs.statut ?? null,
    p_date_activation: champs.date_activation ?? null,
    p_actif: champs.actif ?? false,
    p_matricule_silae: champs.matricule_silae ?? null,
  });
  if (rErr) return json({ ok: false, error: rErr.message || "Échec de la création" }, 500);

  // 5. Téléphone (non géré par la RPC)
  let tel_ok = true;
  if (champs.telephone) {
    const { error: eTel } = await supabase.from("collaborateurs").update({ telephone: champs.telephone }).eq("collab_id", collab_id);
    if (eTel) tel_ok = false;
  }

  return json({ ok: true, collab_id, token, tel_ok });
});
