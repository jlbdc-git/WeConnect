import { SignJWT } from "npm:jose@4.14.4";
import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_VOICE_USERS = 20;
const TOKEN_TTL_SECONDS = 60 * 60 * 2;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return json(
      {
        error: "METHOD_NOT_ALLOWED",
      },
      405,
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";

  if (!authHeader.startsWith("Bearer ")) {
    return json(
      {
        error: "UNAUTHENTICATED",
      },
      401,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error(
      "voice-token: Supabase environment variables missing",
    );

    return json(
      {
        error: "SUPABASE_NOT_CONFIGURED",
      },
      503,
    );
  }

  const supabase = createClient(
    supabaseUrl,
    supabaseAnonKey,
    {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    },
  );

  const {
    data: userData,
    error: userErr,
  } = await supabase.auth.getUser();

  const user = userData?.user;

  if (userErr || !user) {
    return json(
      {
        error: "UNAUTHENTICATED",
      },
      401,
    );
  }

  let body: unknown;

  try {
    body = await req.json();
  } catch {
    return json(
      {
        error: "BAD_JSON",
      },
      400,
    );
  }

  const channelId =
    typeof body === "object" &&
    body !== null &&
    "channel_id" in body &&
    typeof (body as { channel_id?: unknown }).channel_id === "string"
      ? (body as { channel_id: string }).channel_id.trim()
      : "";

  if (!channelId) {
    return json(
      {
        error: "CHANNEL_ID_REQUIRED",
      },
      400,
    );
  }

  const {
    data: channel,
    error: channelError,
  } = await supabase
    .from("channels")
    .select("id, server_id, kind, name")
    .eq("id", channelId)
    .maybeSingle();

  if (channelError) {
    console.error(
      "voice-token: channel lookup failed",
      channelError,
    );

    return json(
      {
        error: "CHANNEL_LOOKUP_FAILED",
      },
      500,
    );
  }

  if (!channel) {
    return json(
      {
        error: "CHANNEL_NOT_FOUND",
      },
      404,
    );
  }

  if (channel.kind !== "voice") {
    return json(
      {
        error: "NOT_A_VOICE_CHANNEL",
      },
      403,
    );
  }

  const {
    data: member,
    error: memberError,
  } = await supabase
    .from("server_members")
    .select("profile_id")
    .eq("server_id", channel.server_id)
    .eq("profile_id", user.id)
    .maybeSingle();

  if (memberError) {
    console.error(
      "voice-token: membership check failed",
      memberError,
    );

    return json(
      {
        error: "MEMBERSHIP_CHECK_FAILED",
      },
      500,
    );
  }

  if (!member) {
    return json(
      {
        error: "NOT_A_MEMBER",
      },
      403,
    );
  }

  const {
    count,
    error: countError,
  } = await supabase
    .from("voice_participants")
    .select("profile_id", {
      count: "exact",
      head: true,
    })
    .eq("channel_id", channelId);

  if (countError) {
    console.warn(
      "voice-token: voice_participants count unavailable",
      countError,
    );
  } else if (
    count !== null &&
    count >= MAX_VOICE_USERS
  ) {
    return json(
      {
        error: "CHANNEL_FULL",
        capacity: MAX_VOICE_USERS,
        current: count,
      },
      409,
    );
  }

  const livekitApiKey =
    Deno.env.get("LIVEKIT_API_KEY");

  const livekitApiSecret =
    Deno.env.get("LIVEKIT_API_SECRET");

  const livekitUrl =
    Deno.env.get("LIVEKIT_URL");

  if (
    !livekitApiKey ||
    !livekitApiSecret ||
    !livekitUrl
  ) {
    console.error(
      "voice-token: LiveKit secrets are not configured",
    );

    return json(
      {
        error: "VOICE_NOT_CONFIGURED",
      },
      503,
    );
  }

  const roomName = `wc_${channelId}`;

  const grants = {
    room: roomName,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  };

  const now = Math.floor(Date.now() / 1000);

  // Authoritative 20-user cap, enforced by the LiveKit server itself.
  // The DB count above is advisory (fast reject); a roomConfig claim makes
  // the limit race-free: even if two joins pass the count check
  // simultaneously, LiveKit rejects the 21st participant at connect time.
  const video = {
    ...grants,
    roomConfig: {
      max_participants: MAX_VOICE_USERS,
    },
  };

  const token = await new SignJWT({
    video,
    name: user.id,
  })
    .setProtectedHeader({
      alg: "HS256",
      typ: "JWT",
    })
    .setIssuer(livekitApiKey)
    .setSubject(user.id)
    .setJti(crypto.randomUUID())
    .setIssuedAt(now)
    .setNotBefore(now)
    .setExpirationTime(now + TOKEN_TTL_SECONDS)
    .sign(
      new TextEncoder().encode(livekitApiSecret),
    );

  return json({
    token,
    url: livekitUrl,
    roomName,
    identity: user.id,
    capacity: MAX_VOICE_USERS,
  });
});
