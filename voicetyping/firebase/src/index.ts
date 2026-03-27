import { onRequest } from "firebase-functions/v2/https";
import { GoogleGenerativeAI } from "@google/generative-ai";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY ?? "";
const RATE_LIMIT_PER_DEVICE = 30; // requests per minute
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();

function checkRateLimit(deviceId: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(deviceId);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(deviceId, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  if (entry.count >= RATE_LIMIT_PER_DEVICE) return false;
  entry.count++;
  return true;
}

const SYSTEM_PROMPT = `You are a voice-to-text formatter. Your job is to clean up speech transcriptions.

Rules:
1. Remove filler words (えー, あの, うーん, um, uh, like, you know)
2. Detect self-corrections: keep only the final version
   Example: "明日、いや明後日" → "明後日"
3. Add proper punctuation (。、！？ for Japanese; .,!? for English)
4. Convert spoken grammar to written grammar
5. Preserve the speaker's meaning exactly — do NOT add content
6. Keep the same language as input
7. If mixed languages, preserve the mixing naturally

Output ONLY the cleaned text. No explanations.`;

const MODE_INSTRUCTIONS: Record<string, string> = {
  casual: "Light cleanup, keep conversational tone.",
  business: "Formal, polite. Use 敬語 for Japanese.",
  technical: "Clear, precise instruction language.",
  raw: "",
};

export const formatText = onRequest(
  { cors: true, region: "asia-northeast1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const { text, mode = "casual", deviceId = "unknown" } = req.body;

    if (!text || typeof text !== "string" || text.trim().length === 0) {
      res.status(400).json({ error: "Missing text" });
      return;
    }

    if (mode === "raw") {
      res.json({ result: text });
      return;
    }

    if (!checkRateLimit(deviceId)) {
      res.status(429).json({ error: "Rate limited" });
      return;
    }

    try {
      const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
      const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

      const modeInstruction = MODE_INSTRUCTIONS[mode] ?? MODE_INSTRUCTIONS.casual;
      const prompt = `${SYSTEM_PROMPT}\n\nMode: ${mode}\n${modeInstruction}\n\nTranscription to clean:\n${text}`;

      const result = await model.generateContent(prompt);
      const cleaned = result.response.text().trim();

      res.json({ result: cleaned });
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : "Unknown error";
      res.status(500).json({ error: message });
    }
  }
);
