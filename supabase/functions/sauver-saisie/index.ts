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

// Durée d'un créneau en heures décimales (equiv. diff() du front)
function diff(a: string, b: string): number {
  if (!a || !b) return 0;
  const [h1, m1] = a.split(":").map(Number);
  const [h2, m2] = b.split(":").map(Number);
  if ([h1, m1, h2, m2].some((n) => Number.isNaN(n))) return 0;
  return Math.max(0, (h2 * 60 + m2 - (h1 * 60 + m1)) / 60);
}

// Somme des 3 créneaux (equiv. calculTotal() du front)
function calculTotal(c: Record<string, string>): number {
  let t = 0;
  if (c.c1_debut && c.c1_fin) t += diff(c.c1_debut, c.c1_fin);
  if (c.c2_debut && c.c2_fin) t += diff(c.c2_debut, c.c2_fin);
  if (c.c3_debut && c.c3_fin) t += diff(c.c3_debut, c.c3_fin);
  return t;
}

function toUTCms(iso: string): number {
  const [y, m, d] = iso.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

// Lundi de la semaine d'une date 'YYYY-MM-DD' (calcul date pur)
function lundiDeLaSemaine(iso: string): string {
  const d = new Date(iso + "T00:00:00Z");
  const js = d.getUTCDay();          // 0=dim..6=sam
  const dow = js === 0 ? 6 : js - 1; // 0=lun..6=dim
  d.setUTCDate(d.getUTCDate() - dow);
  return d.toISOString().slice(0, 10);
}

// Date du jour + horodatage, en Europe/Paris
function parisNow(): { dateISO: string; stamp: string } {
  const now = new Date();
  const dateISO = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);
  const d = new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris", day: "2-digit", month: "2-digit", year: "numeric",
  }).format(now);
  const t = new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit",
  }).format(now);
  return { dateISO, stamp: `${d} ${t} (collab)` };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Methode non autorisee" }, 405);

  let p: any;
  try { p = await req.json(); } catch { return json({ ok: false, error: "JSON invalide" }, 400); }

  const collab_token = (p?.collab_token ?? "").toString().trim();
  const jour_id = (p?.jour_id ?? "").toString().trim();
  const type_jour = (p?.type_jour ?? "").toString().trim();
  const commentaire = (p?.commentaire ?? "").toString();
  const creneaux = {
    c1_debut: (p?.c1_debut ?? "").toString(), c1_fin: (p?.c1_fin ?? "").toString(),
    c2_debut: (p?.c2_debut ?? "").toString(), c2_fin: (p?.c2_fin ?? "").toString(),
    c3_debut: (p?.c3_debut ?? "").toString(), c3_fin: (p?.c3_fin ?? "").toString(),
  };

  if (!collab_token || !jour_id) return json({ ok: false, error: "collab_token et jour_id requis" }, 400);

  const TYPES_AUTORISES = ["travaillée", "CP", "AT"];
  if (!TYPES_AUTORISES.includes(type_jour)) {
    return json({ ok: false, error: "Type de jour non autorisé en saisie collaborateur" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // 1. Auth collaborateur via token
  const { data: collab, error: cErr } = await supabase
    .from("collaborateurs").select("collab_id").eq("token", collab_token).maybeSingle();
  if (cErr) return json({ ok: false, error: "Erreur base (collaborateurs)" }, 500);
  if (!collab) return json({ ok: false, error: "Collaborateur non reconnu" }, 401);

  // 2. Charger le jour
  const { data: jour, error: jErr } = await supabase
    .from("jours").select("jour_id, collab_id, date_jour, periode_id, nb_modifications")
    .eq("jour_id", jour_id).maybeSingle();
  if (jErr) return json({ ok: false, error: "Erreur base (jours)" }, 500);
  if (!jour) return json({ ok: false, error: "Jour introuvable" }, 404);

  // 3. Appartenance
  if (jour.collab_id !== collab.collab_id) {
    return json({ ok: false, error: "Ce jour ne vous appartient pas" }, 403);
  }

  // 4. Statut de la période
  const { data: periode, error: pErr } = await supabase
    .from("periodes").select("statut").eq("periode_id", jour.periode_id).maybeSingle();
  if (pErr) return json({ ok: false, error: "Erreur base (periodes)" }, 500);
  if (!periode || periode.statut !== "ouverte") {
    const msg = periode?.statut === "cloturee" ? "Période clôturée"
      : periode?.statut === "gelee" ? "Période gelée"
      : "Saisie fermée pour cette période";
    return json({ ok: false, error: msg }, 403);
  }

  // 5. Fenêtre J-5
  const { dateISO: todayISO, stamp } = parisNow();
  const jourISO = (jour.date_jour ?? "").toString().slice(0, 10);
  const joursDepuis = Math.round((toUTCms(todayISO) - toUTCms(jourISO)) / 86400000);
  if (joursDepuis > 5) return json({ ok: false, error: "Délai de 5 jours dépassé" }, 403);

  // 6. Limite 3 modifications (source de vérité = base)
  const nbModifs = Number(jour.nb_modifications) || 0;
  if (nbModifs >= 3) return json({ ok: false, error: "3 modifications maximum atteintes" }, 403);

  // 7. Recalcul serveur des totaux
  const isAbsence = type_jour !== "travaillée";
  const totalJour = isAbsence ? 0 : calculTotal(creneaux);
  const lundiISO = lundiDeLaSemaine(jourISO);
  const { data: joursSemaine, error: sErr } = await supabase
    .from("jours").select("total_heures, jour_id")
    .eq("collab_id", collab.collab_id).gte("date_jour", lundiISO).lte("date_jour", jourISO);
  if (sErr) return json({ ok: false, error: "Erreur base (cumul hebdo)" }, 500);
  let hebdoProg = totalJour;
  for (const j of joursSemaine ?? []) {
    if (j.jour_id !== jour_id) hebdoProg += Number(j.total_heures) || 0;
  }

  // 8. Écriture
  const { error: uErr } = await supabase.from("jours").update({
    type_jour,
    c1_debut: isAbsence ? "" : creneaux.c1_debut, c1_fin: isAbsence ? "" : creneaux.c1_fin,
    c2_debut: isAbsence ? "" : creneaux.c2_debut, c2_fin: isAbsence ? "" : creneaux.c2_fin,
    c3_debut: isAbsence ? "" : creneaux.c3_debut, c3_fin: isAbsence ? "" : creneaux.c3_fin,
    commentaire,
    total_heures: totalJour,
    total_hebdo_prog: hebdoProg,
    nb_modifications: nbModifs + 1,
    date_derniere_modif: stamp,
  }).eq("jour_id", jour_id);
  if (uErr) return json({ ok: false, error: "Échec de l'enregistrement" }, 500);

  return json({ ok: true, total_heures: totalJour, total_hebdo_prog: hebdoProg,
    nb_modifications: nbModifs + 1, date_derniere_modif: stamp });
});
