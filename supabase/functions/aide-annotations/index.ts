import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Notes des administrateurs sur le guide (onglet « Aide » de admin-v2.html).
// Auteur = nom renvoyé par verifier_admin, jamais pris dans le body.

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

const COLONNES = "id, section, nature, texte, auteur, cree_le, traitee, traitee_par, traitee_le";

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

  const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
  if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
  if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

  if (action === "liste") {
    const { data, error } = await supabase.from("aide_annotations")
      .select(COLONNES).eq("retiree", false).order("cree_le", { ascending: true });
    if (error) return json({ ok: false, error: "Échec de la lecture des notes" }, 500);
    return json({ ok: true, admin: adminNom, annotations: data ?? [] });
  }

  if (action === "ajouter") {
    const section = (p?.section ?? "").toString().trim();
    const nature = (p?.nature ?? "").toString().trim();
    const texte = (p?.texte ?? "").toString().trim();
    if (!section || section.length > 200) return json({ ok: false, error: "section invalide" }, 400);
    if (nature !== "correction" && nature !== "pratique") return json({ ok: false, error: "nature invalide" }, 400);
    if (!texte || texte.length > 2000) return json({ ok: false, error: "Texte vide ou trop long (2000 caractères max)" }, 400);
    const { data, error } = await supabase.from("aide_annotations")
      .insert({ section, nature, texte, auteur: adminNom }).select(COLONNES).single();
    if (error) return json({ ok: false, error: "Échec de l'enregistrement de la note" }, 500);
    return json({ ok: true, admin: adminNom, annotation: data });
  }

  if (action === "traiter" || action === "retirer") {
    const id = Number(p?.id);
    if (!Number.isInteger(id) || id <= 0) return json({ ok: false, error: "id invalide" }, 400);
    const maj = action === "traiter"
      ? { traitee: true, traitee_par: adminNom, traitee_le: new Date().toISOString() }
      : { retiree: true };
    const { data, error } = await supabase.from("aide_annotations")
      .update(maj).eq("id", id).eq("retiree", false).select(COLONNES);
    if (error) return json({ ok: false, error: "Échec de la mise à jour de la note" }, 500);
    if (!data || data.length === 0) return json({ ok: false, error: "Note introuvable" }, 404);
    return json({ ok: true, admin: adminNom, annotation: data[0] });
  }

  return json({ ok: false, error: "Action inconnue" }, 400);
});
