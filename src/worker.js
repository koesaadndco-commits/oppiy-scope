/* Cloudflare Worker:静的ファイル(public/)の配信 + AIコーチ API
   ブラウザ → POST /api/coach → ここで Claude API を呼ぶ。APIキーはブラウザに出さない。
   それ以外のパスは public/ の静的ファイルをそのまま返す(wrangler.jsonc の assets)。
   Secrets(Cloudflare → Workers & Pages → oppiy-scope → Settings → Variables and Secrets):
     ANTHROPIC_API_KEY  … 必須
   任意の環境変数:
     COACH_MODEL        … 既定 claude-opus-5-5
   ログイン済みユーザーだけが使えるよう、Supabase のアクセストークンを検証する。

   npm のビルド工程を持たない静的サイトなので、SDK ではなく fetch で直接 Messages API を呼ぶ。 */

const SUPABASE_URL = "https://xnjcanoibshixxcjejii.supabase.co";
const SUPABASE_KEY = "sb_publishable_A1rVNffy4RtpYCPCKD4PDA_Dc3vCRos";
const API_URL = "https://api.anthropic.com/v1/messages";
const MAX_PROMPT_CHARS = 60000;

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });

async function verifyUser(req) {
  const auth = req.headers.get("authorization") || "";
  if (!auth.startsWith("Bearer ")) return null;
  const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: SUPABASE_KEY, authorization: auth } });
  if (!r.ok) return null;
  const u = await r.json();
  return u?.id ? u : null;
}

async function coach(request, env) {
  if (!env.ANTHROPIC_API_KEY) return json({ error: "not_configured", message: "AIコーチの設定が未完了です(ANTHROPIC_API_KEY 未登録)。" }, 503);

  const user = await verifyUser(request);
  if (!user) return json({ error: "unauthorized", message: "ログインが必要です。" }, 401);

  let body;
  try { body = await request.json(); } catch { return json({ error: "bad_request" }, 400); }
  const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
  if (!prompt) return json({ error: "bad_request", message: "prompt がありません。" }, 400);
  if (prompt.length > MAX_PROMPT_CHARS) return json({ error: "bad_request", message: "入力が長すぎます。" }, 413);

  const res = await fetch(API_URL, {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "anthropic-beta": "server-side-fallback-2026-07-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: env.COACH_MODEL || "claude-opus-5-5",
      max_tokens: 4096,
      fallbacks: "default",
      output_config: { effort: "medium" },
      system: "あなたはダンススタジオの講師です。生徒の練習動画を姿勢推定で数値化したデータを読み、数値に基づいて具体的に、日本語で講評します。データに無いことは書きません。",
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (res.status === 429) return json({ error: "rate_limited", message: "混み合っています。少し時間をおいてから試してください。" }, 429);
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    console.error("anthropic error", res.status, detail.slice(0, 500));
    return json({ error: "upstream", message: "コメントを作れませんでした。" }, 502);
  }
  const msg = await res.json();
  if (msg.stop_reason === "refusal") return json({ error: "refused", message: "この内容にはコメントできませんでした。" }, 422);
  const text = (msg.content || []).filter(b => b.type === "text").map(b => b.text).join("").trim();
  if (!text) return json({ error: "empty", message: "コメントを作れませんでした。" }, 502);
  return json({ text, model: msg.model });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/coach") {
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
      return coach(request, env);
    }
    return env.ASSETS.fetch(request);
  },
};
