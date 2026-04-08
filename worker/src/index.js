// PGA Pool Worker — Phase 2
// Cron every 2min: fetch ESPN PGA scoreboard, upsert tournaments + tournament_golfers
// Auto-detects cut, updates positions/scores live.

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(sync(env));
  },
  async fetch(request, env) {
    const result = await sync(env);
    return new Response(JSON.stringify(result, null, 2), {
      headers: { 'content-type': 'application/json' }
    });
  }
};

async function sync(env) {
  try {
    const resp = await fetch(env.ESPN_URL);
    if (!resp.ok) return { error: 'espn fetch failed', status: resp.status };
    const json = await resp.json();

    const ev = (json.events || [])[0];
    if (!ev) return { error: 'no event' };

    const comp = (ev.competitions || [])[0];
    if (!comp) return { error: 'no competition' };

    // 1. Upsert tournament
    const state = ev.status?.type?.state; // pre | in | post
    const statusMap = { pre: 'upcoming', in: 'in_progress', post: 'finished' };
    const tournamentPayload = {
      name: ev.name,
      espn_event_id: ev.id,
      par: comp.course?.totalPar || 72,
      status: statusMap[state] || 'upcoming',
      start_date: ev.date ? ev.date.slice(0, 10) : null
    };

    const tUrl = `${env.SUPABASE_URL}/rest/v1/tournaments?on_conflict=espn_event_id`;
    const tResp = await fetch(tUrl, {
      method: 'POST',
      headers: sbHeaders(env, { Prefer: 'resolution=merge-duplicates,return=representation' }),
      body: JSON.stringify(tournamentPayload)
    });
    if (!tResp.ok) return { error: 'tournament upsert failed', status: tResp.status, body: await tResp.text() };
    const [tournament] = await tResp.json();

    // 2. Upsert all competitors as tournament_golfers
    const competitors = comp.competitors || [];
    const golferRows = competitors.map(c => {
      const athlete = c.athlete || {};
      const name = athlete.displayName || athlete.shortName || '';
      if (!name) return null;

      // total_score: toPar int
      const scoreStr = c.score || '';
      const total = parseToPar(scoreStr);

      // position
      const position = c.status?.position?.displayName || null;

      // thru
      const thru = c.status?.thru?.toString() || null;

      // status: active | cut | wd | dq
      const typeName = (c.status?.type?.name || '').toUpperCase();
      let gStatus = 'active';
      if (typeName.includes('CUT')) gStatus = 'cut';
      else if (typeName.includes('WITHDRAW')) gStatus = 'wd';
      else if (typeName.includes('DISQUAL')) gStatus = 'dq';

      // linescores → round1..4
      const ls = c.linescores || [];
      const rounds = [null, null, null, null];
      for (let i = 0; i < ls.length && i < 4; i++) {
        const v = ls[i].value;
        if (typeof v === 'number' && v > 0) rounds[i] = v;
      }

      return {
        tournament_id: tournament.id,
        name,
        espn_id: c.id || null,
        position,
        total_score: total,
        thru,
        round1: rounds[0], round2: rounds[1], round3: rounds[2], round4: rounds[3],
        status: gStatus,
        updated_at: new Date().toISOString()
      };
    }).filter(Boolean);

    // Batch upsert
    const gUrl = `${env.SUPABASE_URL}/rest/v1/tournament_golfers?on_conflict=tournament_id,name`;
    const gResp = await fetch(gUrl, {
      method: 'POST',
      headers: sbHeaders(env, { Prefer: 'resolution=merge-duplicates' }),
      body: JSON.stringify(golferRows)
    });
    if (!gResp.ok) return { error: 'golfers upsert failed', status: gResp.status, body: (await gResp.text()).slice(0, 500) };

    return {
      ok: true,
      tournament: tournament.name,
      state,
      golfers_upserted: golferRows.length
    };
  } catch (e) {
    return { error: e.message, stack: e.stack };
  }
}

function parseToPar(s) {
  if (s === undefined || s === null || s === '') return null;
  if (s === 'E') return 0;
  const n = parseInt(s, 10);
  return isNaN(n) ? null : n;
}

function sbHeaders(env, extra = {}) {
  return {
    'apikey': env.SUPABASE_SERVICE_KEY,
    'Authorization': `Bearer ${env.SUPABASE_SERVICE_KEY}`,
    'Content-Type': 'application/json',
    ...extra
  };
}
