// Supabase Edge Function: advance-draft
// Advances the async draft: auto-picks expired turns, sets next picker, sends APNs.
//
// Setup (once):
//   supabase secrets set APNS_KEY_P8="$(cat AuthKey_XXXXXXXX.p8)"
//   supabase secrets set APNS_KEY_ID=XXXXXXXX
//   supabase secrets set APNS_TEAM_ID=GMVYS2L6UU
//   supabase secrets set APNS_BUNDLE_ID=at.markushabeler.GolfMajorPool
//
// Deploy:
//   supabase functions deploy advance-draft
//
// Called by:
//   - Native app after pick or draft-start
//   - pg_cron every 15 min (no body → process all expired pools)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const APNS_KEY_P8 = Deno.env.get("APNS_KEY_P8") ?? "";
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "at.markushabeler.GolfMajorPool";

const PICK_WINDOW_HOURS = 3;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const body = await req.json().catch(() => ({}));
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    if (body.pool_id) {
      await processPool(sb, body.pool_id as string);
    } else {
      // pg_cron path: process all pools with expired deadlines
      const { data: expired } = await sb
        .from("pools")
        .select("id")
        .in("status", ["draft", "drafting"])
        .not("current_pick_deadline", "is", null)
        .not("current_pick_member_id", "is", null)
        .lt("current_pick_deadline", new Date().toISOString());

      for (const p of expired ?? []) {
        await processPool(sb, p.id).catch(console.error);
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("advance-draft error:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});

// ──────────────────────────────────────────────────────────
// Core: process one pool
// ──────────────────────────────────────────────────────────

async function processPool(sb: ReturnType<typeof createClient>, poolId: string) {
  // Load pool
  const { data: pool } = await sb
    .from("pools")
    .select("*")
    .eq("id", poolId)
    .single();
  if (!pool || !["draft", "drafting"].includes(pool.status)) return;

  // Load members sorted by draft_position
  const { data: members } = await sb
    .from("pool_members")
    .select("*")
    .eq("pool_id", poolId)
    .order("draft_position", { ascending: true });
  if (!members || members.length === 0) return;

  // Load existing picks
  const { data: picks } = await sb
    .from("pool_picks")
    .select("golfer_name")
    .eq("pool_id", poolId);

  const picksCount = picks?.length ?? 0;
  const memberCount = members.length;
  const picksPerMember = pool.picks_per_member ?? 5;
  const totalPicks = memberCount * picksPerMember;

  // Auto-pick if the current deadline has expired
  const deadline = pool.current_pick_deadline
    ? new Date(pool.current_pick_deadline)
    : null;
  const isExpired = deadline && deadline < new Date();

  if (isExpired && pool.current_pick_member_id && picksCount < totalPicks) {
    // Load tournament golfers for best-available pick
    const { data: golfers } = await sb
      .from("tournament_golfers")
      .select("name, total_score, status")
      .eq("tournament_id", pool.tournament_id)
      .order("total_score", { ascending: true, nullsFirst: false });

    const alreadyPicked = new Set((picks ?? []).map((p: any) => normalizeName(p.golfer_name)));
    const best = (golfers ?? []).find(
      (g: any) => !alreadyPicked.has(normalizeName(g.name))
             && !["wd", "dq"].includes((g.status ?? "").toLowerCase())
    );

    if (best) {
      const currentMember = members.find((m: any) => m.id === pool.current_pick_member_id);
      if (currentMember) {
        const roundIdx = Math.floor(picksCount / memberCount);
        await sb.from("pool_picks").insert({
          pool_id: poolId,
          member_id: currentMember.id,
          user_id: currentMember.user_id ?? null,
          golfer_name: best.name,
          draft_round: roundIdx + 1,
          draft_pick: picksCount + 1,
        });
        // picks count advances by 1 for the next logic
        const newPicksCount = picksCount + 1;
        await advancePickPointer(sb, poolId, members, newPicksCount, totalPicks);
        return;
      }
    }
  }

  // Normal path: just advance the pointer (called after a manual pick)
  await advancePickPointer(sb, poolId, members, picksCount, totalPicks);
}

async function advancePickPointer(
  sb: ReturnType<typeof createClient>,
  poolId: string,
  members: any[],
  picksCount: number,
  totalPicks: number,
) {
  if (picksCount >= totalPicks) {
    // Draft complete
    await sb
      .from("pools")
      .update({ current_pick_member_id: null, current_pick_deadline: null })
      .eq("id", poolId);
    return;
  }

  const nextMember = memberOnTheClock(members, picksCount);
  if (!nextMember) return;

  const deadline = new Date(Date.now() + PICK_WINDOW_HOURS * 60 * 60 * 1000).toISOString();
  await sb
    .from("pools")
    .update({
      current_pick_member_id: nextMember.id,
      current_pick_deadline: deadline,
    })
    .eq("id", poolId);

  // Send push notification
  if (nextMember.user_id) {
    const { data: tokenRow } = await sb
      .from("device_tokens")
      .select("token")
      .eq("user_id", nextMember.user_id)
      .order("updated_at", { ascending: false })
      .limit(1)
      .single();

    if (tokenRow?.token) {
      const displayName = nextMember.display_name ?? "Du";
      await sendApns(
        tokenRow.token,
        "Du bist dran! 🏌️",
        `Wähle deinen Golfer. Du hast ${PICK_WINDOW_HOURS} Stunden.`,
      ).catch(console.error);
    }
  }
}

// Snake-order: mirrors PoolDetailViewModel.memberOnTheClock
function memberOnTheClock(members: any[], picksCount: number): any | null {
  const m = members.length;
  if (m === 0) return null;
  const n = picksCount + 1; // 1-indexed pick number
  const roundIdx = Math.floor((n - 1) / m); // 0-indexed round
  const posInRound = (n - 1) % m; // 0-indexed position
  const idx = roundIdx % 2 === 0 ? posInRound : m - 1 - posInRound;
  return members[idx] ?? null;
}

function normalizeName(name: string): string {
  return name.toLowerCase().replace(/[^a-z]/g, "");
}

// ──────────────────────────────────────────────────────────
// APNs via JWT (ES256 / P-256)
// ──────────────────────────────────────────────────────────

async function createApnsJwt(): Promise<string> {
  const pem = APNS_KEY_P8
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const b64url = (s: string) =>
    btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

  const header = b64url(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }));
  const payload = b64url(
    JSON.stringify({ iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }),
  );
  const sigInput = `${header}.${payload}`;

  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(sigInput),
  );

  const sigB64 = b64url(String.fromCharCode(...new Uint8Array(sig)));
  return `${sigInput}.${sigB64}`;
}

async function sendApns(deviceToken: string, title: string, body: string): Promise<void> {
  if (!APNS_KEY_P8 || !APNS_KEY_ID || !APNS_TEAM_ID) {
    console.log("APNs not configured — skipping push");
    return;
  }

  const jwt = await createApnsJwt();
  const res = await fetch(`https://api.push.apple.com/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: { alert: { title, body }, sound: "default", badge: 1 },
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`APNs ${res.status}: ${err}`);
  }
}
