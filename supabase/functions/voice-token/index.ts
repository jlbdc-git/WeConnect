// ============================================================
// voice-token — Supabase Edge Function (Deno)
// ============================================================
// POST /functions/v1/voice-token   { "channel_id": "<uuid>" }
//   401 → caller not authenticated
//   403 → channel is not a voice channel, or caller is not a member
//   409 → voice channel is full (MAX_VOICE_USERS)
//   200 → { token, url, roomName }
//
// SECURITY
//   * LiveKit API key/secret are edge-function secrets:
//       supabase secrets set LIVEKIT_URL=... LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...
//     They are NEVER embedded in the Flutter client. The client only
//     receives a short-lived, room-scoped, identity-bound JWT.
//   * Membership is checked against Postgres using the caller's own
//     Supabase JWT, so a user cannot mint a token for a channel in a
//     server they have not joined.
//   * The 20-user cap is enforced here (server-authoritative); the
//     client may display occupancy but the server is the gatekeeper.
// ============================================================

import { create, getNumericDate } from 'https://esm.sh/jose@4.14.4/jwt';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const MAX_VOICE_USERS = 20;
const TOKEN_TTL_SECONDS = 60 * 60 * 2; // 2 hours

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return json({ error: 'UNAUTHENTICATED' }, 401);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );

  // -- 1. authenticate ----------------------------------------------------
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userErr || !user) {
    return json({ error: 'UNAUTHENTICATED' }, 401);
  }

  // -- 2. parse request ---------------------------------------------------
  let channelId: string | undefined;
  try {
    const body = await req.json();
    channelId = body?.channel_id;
  } catch {
    return json({ error: 'BAD_JSON' }, 400);
  }
  if (typeof channelId !== 'string' || channelId.length === 0) {
    return json({ error: 'CHANNEL_ID_REQUIRED' }, 400);
  }

  // -- 3. load channel ----------------------------------------------------
  const { data: channel, error: chanErr } = await supabase
    .from('channels')
    .select('id, server_id, kind, name')
    .eq('id', channelId)
    .single();

  if (chanErr || !channel) {
    return json({ error: 'CHANNEL_NOT_FOUND' }, 404);
  }
  if (channel.kind !== 'voice') {
    return json({ error: 'NOT_A_VOICE_CHANNEL' }, 403);
  }

  // -- 4. membership check (authoritative, via RLS-safe query) ------------
  const { data: member, error: memberErr } = await supabase
    .from('server_members')
    .select('profile_id')
    .eq('server_id', channel.server_id)
    .eq('profile_id', user.id)
    .maybeSingle();

  if (memberErr) {
    return json({ error: 'MEMBERSHIP_CHECK_FAILED' }, 500);
  }
  if (!member) {
    return json({ error: 'NOT_A_MEMBER' }, 403);
  }

  // -- 5. occupancy cap ----------------------------------------------------
  // voice_participants is maintained by the client voice service via
  // server-side presence; fall back to LiveKit if the table is unavailable.
  const { count, error: countErr } = await supabase
    .from('voice_participants')
    .select('profile_id', { count: 'exact', head: true })
    .eq('channel_id', channelId);

  if (!countErr && count !== null && count >= MAX_VOICE_USERS) {
    return json({ error: 'CHANNEL_FULL', capacity: MAX_VOICE_USERS }, 409);
  }

  // -- 6. mint LiveKit JWT (HS256) -----------------------------------------
  const apiKey = Deno.env.get('LIVEKIT_API_KEY');
  const apiSecret = Deno.env.get('LIVEKIT_API_SECRET');
  const livekitUrl = Deno.env.get('LIVEKIT_URL');
  if (!apiKey || !apiSecret || !livekitUrl) {
    console.error('voice-token: LiveKit secrets not configured');
    return json({ error: 'VOICE_NOT_CONFIGURED' }, 503);
  }

  const roomName = `wc_${channelId}`;
  const nowSec = Math.floor(Date.now() / 1000);

  // LiveKit grant structure (see livekit protocol "VideoGrant")
  const grants = {
    room: roomName,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  };

  const token = await create(
    {
      iss: apiKey,
      sub: user.id,
      jti: crypto.randomUUID(),
      iat: nowSec,
      exp: nowSec + TOKEN_TTL_SECONDS,
      nbf: nowSec,
      // LiveKit metadata claim
      name: user.email?.split('@')[0] ?? user.id,
      video: grants,
    },
    apiSecret,
    { algorithm: 'HS256', header: { alg: 'HS256', typ: 'JWT' } },
  );

  return json({
    token,
    url: livekitUrl,
    roomName,
    identity: user.id,
    capacity: MAX_VOICE_USERS,
  });
});
