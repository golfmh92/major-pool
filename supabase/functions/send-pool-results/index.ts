// Supabase Edge Function: send-pool-results
// Triggered when a pool is finished. Sends a personalized HTML email to each member.
//
// Setup:
//   1. Resend Account erstellen: https://resend.com
//   2. API Key + verifizierte Sender-Domain
//   3. Secrets setzen:
//      supabase secrets set RESEND_API_KEY=re_xxx
//      supabase secrets set FROM_EMAIL='PGA Pool <pool@deine-domain.com>'
//   4. Deploy:
//      supabase functions deploy send-pool-results
//
// Aufruf aus der App:
//   await sb.functions.invoke('send-pool-results', { body: { pool_id: '...' } });

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") ?? "PGA Pool <pool@example.com>";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { pool_id } = await req.json();
    if (!pool_id) {
      return json({ error: "pool_id required" }, 400);
    }

    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // 1. Snapshot laden
    const { data: result, error: resErr } = await sb
      .from("pool_results")
      .select("snapshot")
      .eq("pool_id", pool_id)
      .single();

    if (resErr || !result) {
      return json({ error: "pool_results not found", details: resErr?.message }, 404);
    }
    const snap = result.snapshot;

    // 2. Member + User-Profile laden
    const { data: members, error: memErr } = await sb
      .from("pool_members")
      .select("user_id, users(name, email)")
      .eq("pool_id", pool_id);

    if (memErr || !members) {
      return json({ error: "members not found", details: memErr?.message }, 404);
    }

    // 3. Pro Member personalisierte Mail
    let sent = 0;
    let failed = 0;
    for (const m of members) {
      const user = (m as any).users;
      if (!user?.email) continue;

      const myRank = snap.ranking.findIndex((r: any) => r.user_id === user.id) + 1;
      const html = buildResultEmail(snap, user, myRank);
      const subject = `🏆 ${snap.name} — Ergebnis`;

      try {
        await sendMail(user.email, subject, html);
        sent++;
      } catch (e) {
        console.error("Mail failed for", user.email, e);
        failed++;
      }
    }

    return json({ ok: true, sent, failed });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sendMail(to: string, subject: string, html: string) {
  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: FROM_EMAIL, to, subject, html }),
  });
  if (!resp.ok) {
    const err = await resp.text();
    throw new Error(`Resend ${resp.status}: ${err}`);
  }
}

function buildResultEmail(snap: any, user: any, myRank: number): string {
  const fmtScore = (n: number | null) => {
    if (n === null || n === undefined) return "—";
    if (n === 0) return "E";
    return n > 0 ? `+${n}` : `${n}`;
  };

  const myTeam = snap.teams.find((t: any) => t.user_id === user.id);
  const golferRows = myTeam?.golfers?.map((g: any) => {
    const total = g.scores.reduce((sum: number, s: number | null) => sum + (s ?? 0), 0);
    const played = g.scores.filter((s: number | null) => s !== null && s > 0).length;
    const toPar = played > 0 ? total - (snap.par * played) : null;
    return `
      <tr>
        <td style="padding:8px 12px;border-bottom:1px solid #eee">${g.name}</td>
        <td style="padding:8px 12px;border-bottom:1px solid #eee;text-align:right">${fmtScore(toPar)}</td>
      </tr>`;
  }).join("") ?? "";

  const rankRows = snap.ranking.map((r: any, i: number) => {
    const isMe = r.user_id === user.id;
    const medal = i === 0 ? "🥇" : i === 1 ? "🥈" : i === 2 ? "🥉" : `${i + 1}.`;
    const bg = isMe ? "background:#e8f5e9;font-weight:600" : "";
    return `
      <tr style="${bg}">
        <td style="padding:8px 12px;border-bottom:1px solid #eee">${medal}</td>
        <td style="padding:8px 12px;border-bottom:1px solid #eee">${r.name}</td>
        <td style="padding:8px 12px;border-bottom:1px solid #eee;text-align:right">${fmtScore(r.total)}</td>
      </tr>`;
  }).join("");

  const payoutRows = snap.payouts.map((p: any) => `
    <tr>
      <td style="padding:8px 12px;border-bottom:1px solid #eee">Platz ${p.rank}</td>
      <td style="padding:8px 12px;border-bottom:1px solid #eee;text-align:right">€${p.amount.toFixed(2)}</td>
    </tr>`).join("");

  return `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:600px;margin:0 auto;padding:20px;color:#1a1d23">
  <div style="background:linear-gradient(135deg,#1B3A5C,#0F2440);color:#fff;padding:24px;border-radius:12px;text-align:center">
    <h1 style="margin:0;font-size:24px;letter-spacing:2px;text-transform:uppercase">${snap.name}</h1>
    <p style="margin:4px 0 0;opacity:.7;font-size:13px">Ergebnis</p>
  </div>

  <div style="margin:24px 0;padding:20px;background:#f7f8fa;border-radius:12px;text-align:center">
    <p style="margin:0;font-size:14px;color:#5a6070">Hi ${user.name},</p>
    <p style="margin:8px 0 0;font-size:18px;font-weight:600">Du bist auf <strong>Platz ${myRank}</strong> gelandet!</p>
  </div>

  <h2 style="font-size:14px;letter-spacing:1px;text-transform:uppercase;color:#5a6070;margin:24px 0 8px">Rangliste</h2>
  <table style="width:100%;border-collapse:collapse;background:#fff;border:1px solid #eee;border-radius:8px;overflow:hidden">
    ${rankRows}
  </table>

  ${golferRows ? `
  <h2 style="font-size:14px;letter-spacing:1px;text-transform:uppercase;color:#5a6070;margin:24px 0 8px">Dein Team</h2>
  <table style="width:100%;border-collapse:collapse;background:#fff;border:1px solid #eee;border-radius:8px;overflow:hidden">
    ${golferRows}
  </table>
  ` : ""}

  <h2 style="font-size:14px;letter-spacing:1px;text-transform:uppercase;color:#5a6070;margin:24px 0 8px">Payouts</h2>
  <p style="margin:0 0 8px;font-size:13px;color:#5a6070">Pot: €${snap.pot.toFixed(2)}</p>
  <table style="width:100%;border-collapse:collapse;background:#fff;border:1px solid #eee;border-radius:8px;overflow:hidden">
    ${payoutRows}
  </table>

  <p style="margin:32px 0 0;font-size:11px;color:#8c93a3;text-align:center">PGA Pool · Automatisch generiert</p>
</body>
</html>`;
}
