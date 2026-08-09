import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const COLS = [
  "periode_id","collab_id","date_jour","jour_semaine","type_jour",
  "c1_debut","c1_fin","c2_debut","c2_fin","c3_debut","c3_fin",
  "total_heures","commentaire","remarque_manager","total_hebdo_prog",
  "nb_modifications","date_derniere_modif","date_cloture",
  "type_jour_valide","heures_valide","ajuste_admin","note_admin",
  "c1_debut_valide","c1_fin_valide","c2_debut_valide","c2_fin_valide","c3_debut_valide","c3_fin_valide",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);
  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const admin_token = (p?.admin_token ?? "").toString().trim();
  const lignes = Array.isArray(p?.lignes) ? p.lignes : null;
  if (!admin_token || !lignes || lignes.length === 0) return json({ ok: false, error: "admin_token et lignes requis" }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  // Bornes de clôture partielle : recap_paie.date_fin_validation non nulle = le collab a été validé
  // jusqu'à cette date. Ses jours AU-DELÀ ne doivent JAMAIS entrer dans paie_detail (sinon un import
  // au gel réinjecterait des jours post-borne générés par le cron → collab avec jours non validés).
  const periodeIds = [...new Set(lignes.map((l: any) => l.periode_id).filter((x: any) => x != null))];
  const bornes = new Map<string, string>();   // clé "periode_id|collab_id" -> date_fin_validation (YYYY-MM-DD)
  if (periodeIds.length) {
    const { data: recaps, error: bErr } = await supabase
      .from("recap_paie")
      .select("collab_id, periode_id, date_fin_validation")
      .in("periode_id", periodeIds)
      .not("date_fin_validation", "is", null);
    // Échec de lecture → 500. On n'importe PAS "au cas où" : mieux vaut un échec visible qu'un import
    // silencieux qui outrepasserait une borne.
    if (bErr) return json({ ok: false, error: bErr.message || "Erreur base (lecture bornes)" }, 500);
    for (const r of (recaps ?? [])) bornes.set(r.periode_id + "|" + r.collab_id, String(r.date_fin_validation).slice(0, 10));
  }

  // Filtre AVANT la whitelist : écarter toute ligne bornée dont date_jour dépasse la borne.
  // Comparaison sur les 10 premiers caractères (YYYY-MM-DD) des deux côtés → indépendante du fuseau.
  const lignesRetenues = lignes.filter((l: any) => {
    const borne = bornes.get(l.periode_id + "|" + l.collab_id);
    if (!borne) return true;
    return String(l.date_jour).slice(0, 10) <= borne;
  });
  const ecartees = lignes.length - lignesRetenues.length;

  if (lignesRetenues.length === 0) {
    return json({ ok: true, importe: false, n: 0, message: "toutes lignes hors borne", ecartees });
  }

  const rows = lignesRetenues.map((l: any) => { const r: Record<string, unknown> = {}; for (const k of COLS) if (k in l) r[k] = l[k]; return r; });
  const { error: iErr } = await supabase.from("paie_detail").upsert(rows, { onConflict: "periode_id,collab_id,date_jour", ignoreDuplicates: true });
  if (iErr) return json({ ok: false, error: iErr.message || "Échec de l'import" }, 500);
  return json({ ok: true, importe: true, n: rows.length, ecartees });
});
