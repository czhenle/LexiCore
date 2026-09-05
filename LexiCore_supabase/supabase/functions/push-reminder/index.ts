// ============================================================================
// LexiCore — Smart daily study reminder (Supabase Edge Function, Deno)
// ----------------------------------------------------------------------------
// The on-device reminder in NotificationService fires blind: it says "Today's
// Task is waiting!" at the student's chosen time whether or not they already
// finished, because a locally scheduled notification cannot check server state
// at the moment it fires. This function is the server-side half that can:
//
//   1. work out what the student's LOCAL time is right now (from their stored
//      IANA timezone — the server has no other way to know when "17:00" is for
//      this particular student),
//   2. look up today's entry in their study plan,
//   3. stay silent if today's task is already done, or today is a rest day,
//   4. otherwise push a reminder that NAMES the actual task.
//
// Meant to be called on a schedule (pg_cron, every 15 minutes). Each student
// gets at most one reminder per their own local day, tracked by
// notification_prefs.last_sent_on.
//
// DRY RUN: with no FCM secrets configured, or with {"dry_run": true} in the
// body, it runs the entire selection and reports who WOULD be pushed and why —
// so all of this logic is testable before a Firebase project even exists.
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

// ── FCM HTTP v1 auth ────────────────────────────────────────────────────────
// The legacy server-key API was shut down in 2024, so this uses HTTP v1: sign a
// JWT with the service account's private key, then trade it for an access token.

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/\\n/g, "\n") // secret stores commonly hold the PEM with literal \n
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(clientEmail: string, privateKeyPem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;

  const key = await importPrivateKey(privateKeyPem);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${b64url(new Uint8Array(sig))}`,
    }),
  });
  const payload = await res.json();
  if (!payload.access_token) {
    throw new Error(`FCM token exchange failed: ${JSON.stringify(payload)}`);
  }
  return payload.access_token as string;
}

/** Returns "UNREGISTERED" when FCM says the token is dead and should be dropped. */
async function sendPush(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
): Promise<string> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          // Same channel NotificationService already creates on the device, so
          // a pushed reminder looks identical to a locally scheduled one.
          android: {
            priority: "high",
            notification: { channel_id: "daily_study_reminder" },
          },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    },
  );
  if (res.ok) return "ok";
  const err = await res.text();
  if (res.status === 404 || err.includes("UNREGISTERED") || err.includes("InvalidRegistration")) {
    return "UNREGISTERED";
  }
  return err.slice(0, 300);
}

// ── Local-time helpers ──────────────────────────────────────────────────────

/** The student's own wall-clock date/time, derived from their IANA timezone. */
function localParts(timezone: string, now: Date) {
  try {
    const parts = Object.fromEntries(
      new Intl.DateTimeFormat("en-CA", {
        timeZone: timezone,
        year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", hour12: false,
      })
        .formatToParts(now)
        .map((p) => [p.type, p.value]),
    );
    return {
      date: `${parts.year}-${parts.month}-${parts.day}`,
      minutes: (Number(parts.hour) % 24) * 60 + Number(parts.minute),
      ok: true,
    };
  } catch {
    return { date: "", minutes: 0, ok: false }; // unknown / malformed timezone
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    // Caller must hold the SERVICE ROLE key, not just any valid JWT. The
    // gateway's verify_jwt would also accept the publishable key, which is
    // embedded in the shipped app — and anyone with it could otherwise
    // trigger the sweep and burn every student's one-per-day reminder.
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const auth = req.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${serviceKey}`) {
      // Prefix only (never the full key) - enough to tell a legacy JWT
      // ("eyJ...") from the newer sb_secret_... format apart while debugging
      // a 403, without exposing anything actually sensitive.
      return json({
        error: "forbidden",
        got_prefix: auth.replace(/^Bearer /, "").slice(0, 12) || null,
        expected_prefix: serviceKey.slice(0, 12),
      }, 403);
    }

    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const onlyUser: string | undefined = body.user_id;

    const projectId = Deno.env.get("FCM_PROJECT_ID");
    const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
    const privateKey = Deno.env.get("FCM_PRIVATE_KEY");
    // Nothing configured yet -> still run the whole selection, just report it.
    const dryRun = body.dry_run === true || !projectId || !clientEmail || !privateKey;

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // ── Diagnostics ─────────────────────────────────────────────────────────
    // Push has four independent things that can be broken (credentials, the
    // device token, delivery, the schedule logic). These two modes isolate the
    // first three so a silent notification can actually be diagnosed instead
    // of guessed at.

    // {"check_auth": true} — do the Google credentials work? Nothing is sent.
    // Much the most common failure is FCM_PRIVATE_KEY losing its newlines.
    if (body.check_auth === true) {
      const missing: string[] = [];
      if (!projectId) missing.push("FCM_PROJECT_ID");
      if (!clientEmail) missing.push("FCM_CLIENT_EMAIL");
      if (!privateKey) missing.push("FCM_PRIVATE_KEY");
      if (missing.length) return json({ ok: false, missing });
      try {
        const token = await getAccessToken(clientEmail!, privateKey!);
        return json({
          ok: true,
          project_id: projectId,
          client_email: clientEmail,
          access_token_preview: `${token.slice(0, 12)}…`,
        });
      } catch (e) {
        return json({ ok: false, error: e instanceof Error ? e.message : String(e) });
      }
    }

    // {"test_push": true, "user_id": "…"} — send to that student's devices
    // right now, ignoring their schedule, reminder time and last_sent_on.
    // Proves delivery end to end without having to fake a study plan.
    if (body.test_push === true) {
      if (!onlyUser) return json({ error: "test_push requires user_id" }, 400);
      if (dryRun) return json({ error: "FCM secrets not configured" }, 400);

      const { data: tokens } = await sb
        .from("device_tokens")
        .select("token")
        .eq("user_id", onlyUser);
      if (!tokens?.length) {
        return json({ error: "no device_tokens rows for that user_id" }, 404);
      }

      const accessToken = await getAccessToken(clientEmail!, privateKey!);
      const results = [];
      for (const t of tokens) {
        results.push({
          token: `${t.token.slice(0, 16)}…`,
          result: await sendPush(
            projectId!,
            accessToken,
            t.token,
            "LexiCore test push 🔔",
            "If you can see this, FCM is working.",
          ),
        });
      }
      return json({ test_push: true, results });
    }

    let query = sb.from("notification_prefs").select("*").eq("enabled", true);
    if (onlyUser) query = query.eq("user_id", onlyUser);
    const { data: prefs, error: prefsErr } = await query;
    if (prefsErr) return json({ error: prefsErr.message }, 500);

    const now = new Date();
    const due: { user_id: string; localDate: string; title: string; body: string }[] = [];
    const skipped: { user_id: string; reason: string }[] = [];

    for (const p of prefs ?? []) {
      const local = localParts(p.timezone, now);
      if (!local.ok) {
        skipped.push({ user_id: p.user_id, reason: `bad_timezone:${p.timezone}` });
        continue;
      }
      // At most one nudge per the student's own local day.
      if (p.last_sent_on === local.date) {
        skipped.push({ user_id: p.user_id, reason: "already_sent_today" });
        continue;
      }
      // Anything at or after their chosen time counts, rather than a narrow
      // window — a late or missed cron tick shouldn't cost them the reminder.
      const dueAt = p.reminder_hour * 60 + p.reminder_minute;
      if (local.minutes < dueAt) {
        skipped.push({ user_id: p.user_id, reason: "not_due_yet" });
        continue;
      }

      const { data: sched } = await sb
        .from("study_schedules")
        .select("plan")
        .eq("user_id", p.user_id)
        .maybeSingle();

      const plan = sched?.plan as Record<string, unknown> | undefined;
      const days = (plan?.days ?? []) as Record<string, unknown>[];
      const today = days.find((d) => d.date === local.date);
      if (!today) {
        skipped.push({ user_id: p.user_id, reason: "no_plan_entry_for_today" });
        continue;
      }
      if (today.type === "rest") {
        skipped.push({ user_id: p.user_id, reason: "rest_day" });
        continue;
      }
      const completed = (plan?.completed_days ?? []) as string[];
      if (completed.includes(local.date)) {
        // The entire reason this runs server-side rather than on the device.
        skipped.push({ user_id: p.user_id, reason: "already_completed" });
        continue;
      }

      const label = (today.task_label as string) ?? "your English practice";
      due.push({
        user_id: p.user_id,
        localDate: local.date,
        title: "Today's Task is waiting! 📚",
        body: `${label} — ready when you are!`,
      });
    }

    if (dryRun) {
      return json({
        dry_run: true,
        reason: body.dry_run === true ? "requested" : "FCM secrets not configured",
        checked: prefs?.length ?? 0,
        would_send: due,
        skipped,
      });
    }

    // ── Real send ───────────────────────────────────────────────────────────
    const accessToken = await getAccessToken(clientEmail!, privateKey!);
    let sent = 0;
    const failures: { user_id: string; error: string }[] = [];

    for (const d of due) {
      const { data: tokens } = await sb
        .from("device_tokens")
        .select("token")
        .eq("user_id", d.user_id);

      if (!tokens?.length) {
        skipped.push({ user_id: d.user_id, reason: "no_device_tokens" });
        continue;
      }

      let anyDelivered = false;
      for (const t of tokens) {
        const result = await sendPush(projectId!, accessToken, t.token, d.title, d.body);
        if (result === "ok") {
          anyDelivered = true;
        } else if (result === "UNREGISTERED") {
          // App uninstalled, or the token rotated — stop pushing to it.
          await sb.from("device_tokens").delete()
            .eq("user_id", d.user_id).eq("token", t.token);
        } else {
          failures.push({ user_id: d.user_id, error: result });
        }
      }

      if (anyDelivered) {
        sent++;
        // Only mark the day as sent once something actually landed, so a
        // transient FCM failure doesn't silently burn today's reminder.
        await sb.from("notification_prefs")
          .update({ last_sent_on: d.localDate })
          .eq("user_id", d.user_id);
      }
    }

    return json({ checked: prefs?.length ?? 0, due: due.length, sent, skipped, failures });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("push-reminder error:", message);
    return json({ error: message }, 500);
  }
});
