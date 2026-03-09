import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";

admin.initializeApp();

// ✅ EDIT THESE
const OWNER = "YOUR_GITHUB_OWNER";
const REPO = "YOUR_REPO";
const BRANCH = "main";
const UPLOAD_DIR = "user_uploads";

// Secret name in Firebase
const GITHUB_TOKEN = defineSecret("GITHUB_TOKEN");

async function verifyFirebaseUser(req: any) {
  const authHeader = (req.headers.authorization || "") as string;
  const m = authHeader.match(/^Bearer (.+)$/);
  if (!m) throw new Error("Missing Authorization: Bearer <token>");

  const decoded = await admin.auth().verifyIdToken(m[1]);
  return decoded; // contains uid
}

export const uploadImageToGithub = onRequest(
  {
    region: "us-central1",
    cors: true,
    secrets: [GITHUB_TOKEN],
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({ error: "Use POST" });
        return;
      }

      // 1) Verify logged-in Firebase user
      const user = await verifyFirebaseUser(req);
      const uid = user.uid;

      // 2) Read JSON body
      const { fileBase64, ext } = req.body ?? {};
      if (!fileBase64 || typeof fileBase64 !== "string") {
        res.status(400).json({ error: "fileBase64 required" });
        return;
      }

      const safeExt = String(ext || "jpg")
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "");

      const fileName = `${uid}_${Date.now()}.${safeExt}`;
      const path = `${UPLOAD_DIR}/${fileName}`;

      // 3) GitHub Contents API
      const apiUrl = `https://api.github.com/repos/${OWNER}/${REPO}/contents/${encodeURIComponent(
        path
      )}`;

      const token = GITHUB_TOKEN.value();

      const ghResp = await fetch(apiUrl, {
        method: "PUT",
        headers: {
          Authorization: `token ${token}`,
          Accept: "application/vnd.github+json",
          "Content-Type": "application/json",
          "User-Agent": "firebase-function",
        },
        body: JSON.stringify({
          message: `upload image ${fileName}`,
          content: fileBase64, // base64 only (no data:image/.. prefix)
          branch: BRANCH,
        }),
      });

      const ghJson = await ghResp.json();
      if (!ghResp.ok) {
        res.status(400).json({
          error: "GitHub upload failed",
          status: ghResp.status,
          details: ghJson,
        });
        return;
      }

      // 4) Return RAW URL
      const rawUrl = `https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${path}`;
      res.json({ url: rawUrl, path });
    } catch (e: any) {
      res.status(401).json({ error: String(e?.message ?? e) });
    }
  }
);
