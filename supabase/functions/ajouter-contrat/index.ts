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
  const collab_id = (p?.collab_id ?? "").toString().trim();
  const date_debut = (p?.date_debut ?? "").toString().trim();
  const structure = (p?.structure ?? "").toString().trim();
  const type_contrat = (p?.type_contrat ?? "").toString().trim();
  const type_periode = (p?.type_periode ?? "").toString().trim();
  const matricule_silae = p?.matricule_silae ? String(p.matricule_silae).trim() : null;
  const date_fin = p?.date_fin ? String(p.date_fin).trim() : null;
  const heures_hebdo = (p?.heures_hebdo === "" || p?.heures_hebdo == null) ? null : Number(p.heures_hebdo);

  // date_fin et matricule_silae sont optionnels : NON inclus dans la garde
  if (!admin_token || !collab_id || !date_debut || !structure || !type_contrat || !type_periode) {
    return json({ ok: false, error: "admin_token, collab_id, date_debut, structure, type_contrat, type_periode requis" }, 400);
  }
  if (heures_hebdo !== null && Number.isNaN(heures_hebdo)) {
    return json({ ok: false, error: "heures_hebdo invalide" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Auth admin
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  // 2. Appel de la RPC métier. p_taux_horaire transmis SEULEMENT s'il est présent dans le body
  //    (absent → non envoyé → default null appliqué en base).
  const rpcArgs: Record<string, unknown> = {
    p_collab_id: collab_id,
    p_date_debut: date_debut,
    p_structure: structure,
    p_type_contrat: type_contrat,
    p_type_periode: type_periode,
    p_heures_hebdo: heures_hebdo,
    p_matricule_silae: matricule_silae,
    p_date_fin: date_fin,
  };
  if (p?.taux_horaire !== undefined) {
    const raw = p.taux_horaire;
    if (raw === "" || raw == null) {
      rpcArgs.p_taux_horaire = null;
    } else {
      const th = Number(String(raw).replace(",", "."));   // accepte la virgule décimale française
      if (!Number.isFinite(th)) return json({ ok: false, error: "taux_horaire invalide" }, 400);
      rpcArgs.p_taux_horaire = th;
    }
  }
  const { data: rData, error: rErr } = await supabase.rpc("ajouter_contrat", rpcArgs);
  if (rErr) return json({ ok: false, error: rErr.message || "Échec de l'ajout de contrat" }, 500);

  return json({ ok: true, admin: adminNom, collab_id: rData });
});
