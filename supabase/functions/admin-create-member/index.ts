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
    // Support both current Supabase key bundles and the standard Edge Function
    // environment variables available in existing projects.
    const publishableRaw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}";
    const secretRaw = Deno.env.get("SUPABASE_SECRET_KEYS") || "{}";
    let publishableKeys: Record<string, string> = {};
    let secretKeys: Record<string, string> = {};
    try { publishableKeys = JSON.parse(publishableRaw); } catch { /* use standard env fallback */ }
    try { secretKeys = JSON.parse(secretRaw); } catch { /* use standard env fallback */ }
    const anonKey = publishableKeys.default || Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    const serviceKey = secretKeys.default || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY");
    if (!anonKey || !serviceKey) return respond({ error: "Supabase publishable/secret API keys are not configured" }, 500);
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return respond({ error: "Admin login required" }, 401);

    const verifier = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await verifier.auth.getUser(token);
    if (authError || !authData.user) return respond({ error: "Invalid admin session" }, 401);
    const adminUser = authData.user;
    if ((adminUser.email || "").toLowerCase() !== "acharya.kp65@gmail.com") {
      return respond({ error: "Only the SABKA HISSA Admin can create member logins" }, 403);
    }

    const body = await req.json();
    const memberId = String(body.member_id || "").trim();
    const memberName = String(body.member_name || "").trim();
    const username = String(body.username || "").trim().toLowerCase();
    const email = username + "@members.sabka-hissa.invalid";
    const password = String(body.password || "");
    if (!memberId || !memberName || !/^[a-z0-9][a-z0-9._-]{2,29}$/.test(username) || password.length < 8) {
      return respond({ error: "Member, valid username (3-30 characters) and password of at least 8 characters are required" }, 400);
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: existing, error: existingError } = await admin.from("member_login_accounts").select("member_id").ilike("username", username).maybeSingle();
    if (existingError) return respond({ error: existingError.message }, 400);
    if (existing) return respond({ error: "This username is already in use" }, 409);
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { role: "member", member_id: memberId, member_name: memberName, username }
    });
    if (createError || !created.user) return respond({ error: createError?.message || "Could not create member auth user" }, 400);

    const { error: linkError } = await admin.from("member_login_accounts").insert({
      member_id: memberId, auth_user_id: created.user.id, member_name: memberName,
      username, login_email: email, is_active: true, created_by: adminUser.id
    });
    if (linkError) {
      await admin.auth.admin.deleteUser(created.user.id);
      return respond({ error: linkError.message }, 400);
    }

    const portalData = body.member_data && typeof body.member_data === "object" ? body.member_data : {};
    const { error: portalError } = await admin.from("member_portal_data").insert({
      member_id: memberId, member_data: portalData
    });
    if (portalError) {
      await admin.from("member_login_accounts").delete().eq("member_id", memberId);
      await admin.auth.admin.deleteUser(created.user.id);
      return respond({ error: portalError.message }, 400);
    }

    return respond({ success: true, member_id: memberId, username });
  } catch (error) {
    return respond({ error: error instanceof Error ? error.message : "Unexpected server error" }, 500);
  }
});
