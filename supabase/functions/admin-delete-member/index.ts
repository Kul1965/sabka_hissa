import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const respond = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method !== "POST") return respond({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\\s+/i, "");
    if (!token) return respond({ error: "Admin login required" }, 401);

    const verifier = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await verifier.auth.getUser(token);
    if (authError || !authData.user) return respond({ error: "Invalid admin session" }, 401);
    if ((authData.user.email || "").toLowerCase() !== "acharya.kp65@gmail.com") {
      return respond({ error: "Only the SABKA HISSA Admin can delete member logins" }, 403);
    }

    const body = await req.json();
    const memberId = String(body.member_id || "").trim();
    const mode = String(body.mode || "");
    if (!memberId || !["login_only", "full_member"].includes(mode)) {
      return respond({ error: "Valid member_id and delete mode are required" }, 400);
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: link, error: lookupError } = await admin
      .from("member_login_accounts")
      .select("member_id,auth_user_id")
      .eq("member_id", memberId)
      .maybeSingle();
    if (lookupError) return respond({ error: lookupError.message }, 400);

    if (link) {
      // Remove mapping and private portal row first; Auth user is then permanently removed.
      const { error: mapError } = await admin.from("member_login_accounts").delete().eq("member_id", memberId);
      if (mapError) return respond({ error: mapError.message }, 400);
      const { error: authDeleteError } = await admin.auth.admin.deleteUser(link.auth_user_id);
      if (authDeleteError) return respond({ error: authDeleteError.message }, 400);
    }

    return respond({ success: true, member_id: memberId, mode, login_removed: !!link });
  } catch (error) {
    return respond({ error: error instanceof Error ? error.message : "Unexpected server error" }, 500);
  }
});
