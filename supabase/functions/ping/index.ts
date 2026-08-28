import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Surveillance externe (UptimeRobot, plan gratuit → GET uniquement).
// ⚠️ AUCUNE authentification : pas de token (un token dans un service tiers fuiterait).
// ⚠️ N'EXPOSE AUCUNE DONNEE : la reponse ne contient QUE « ok » ou « ko ».
//   Aucun compte, aucun nom de table, aucune version.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Cache-Control": "no-store",
};

function texte(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, "Content-Type": "text/plain; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  // UptimeRobot gratuit ne fait que du GET ; HEAD accepte aussi la sonde.
  if (req.method !== "GET" && req.method !== "HEAD") {
    return texte("ko", 405);
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Requete triviale : prouve que PostgreSQL repond. Le resultat n'est PAS renvoye
    // (head:true → aucune ligne, seul le count remonte, et on ne l'expose pas).
    const { error } = await supabase
      .from("periodes")
      .select("*", { count: "exact", head: true });

    if (error) return texte("ko", 503);
    return texte("ok", 200);
  } catch {
    return texte("ko", 503);
  }
});
