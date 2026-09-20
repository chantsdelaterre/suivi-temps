import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// '' / 'null' / 'toutes' → null (aucun filtre) ; sinon la valeur.
const orNull = (v: string | null) =>
  (v === null || v === "" || v === "null" || v === "toutes") ? null : v;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // ─── GET : matérialise puis liste ───
  if (req.method === "GET") {
    const url = new URL(req.url);
    const admin_token = (url.searchParams.get("admin_token") ?? "").trim();
    if (!admin_token) return json({ ok: false, error: "admin_token requis" }, 400);

    const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
    if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
    if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

    // statut : défaut 'a_faire' si absent ; explicitement null (''/'null'/'toutes') pour toutes.
    let statut: string | null = "a_faire";
    if (url.searchParams.has("statut")) statut = orNull(url.searchParams.get("statut"));

    // 1. Matérialisation idempotente (sans risque à chaque GET).
    const { error: mErr } = await supabase.rpc("materialiser_journal_taches");
    if (mErr) return json({ ok: false, error: mErr.message || "Échec de la matérialisation" }, 500);

    // 2. Liste filtrée.
    const { data, error } = await supabase.rpc("journal_taches_liste", {
      p_statut: statut,
      p_mouvement: orNull(url.searchParams.get("mouvement")),
      p_type_contrat: orNull(url.searchParams.get("type_contrat")),
      p_tiers: orNull(url.searchParams.get("tiers")),
      p_structure: orNull(url.searchParams.get("structure")),
    });
    if (error) return json({ ok: false, error: error.message || "Échec de la lecture des tâches" }, 500);

    return json({ ok: true, admin: adminNom, taches: data ?? [] });
  }

  // ─── POST : traiter une tâche (faite / sans_objet) ───
  if (req.method === "POST") {
    let p: any;
    try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

    const admin_token = (p?.admin_token ?? "").toString().trim();
    if (!admin_token) return json({ ok: false, error: "admin_token requis" }, 400);

    const { data: adminNom, error: aErr } = await supabase.rpc("verifier_admin", { p_token: admin_token });
    if (aErr) return json({ ok: false, error: "Erreur base (auth admin)" }, 500);
    if (!adminNom) return json({ ok: false, error: "Admin non autorisé" }, 401);

    // Prénom de l'admin. La table `admins` n'a QUE `nom` (pas de `prenom`) et
    // verifier_admin renvoie déjà cette valeur → on la réutilise (option A).
    const prenom = adminNom;

    const id = Number(p?.id);
    if (!Number.isInteger(id) || id <= 0) return json({ ok: false, error: "id requis" }, 400);
    const statut = (p?.statut ?? "").toString().trim();
    const remarque = (p?.remarque ?? null);

    // La base valide le statut ('faite'/'sans_objet'), l'existence de la tâche, etc.
    const { error } = await supabase.rpc("journal_tache_traiter", {
      p_id: id,
      p_statut: statut,
      p_fait_par: prenom,
      p_remarque: remarque,
    });
    if (error) return json({ ok: false, error: error.message || "Échec du traitement de la tâche" }, 500);

    return json({ ok: true, admin: adminNom });
  }

  return json({ ok: false, error: "Methode non autorisee" }, 405);
});
