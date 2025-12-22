import { createServer as createViteServer } from "vite";
import { spawn } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function usage() {
  console.error("usage: cm <file> [--no-open] [--port <port>]");
}

function parseArgs(argv) {
  const args = argv.slice(2);
  let filePath = null;
  let shouldOpen = true;
  let port = 0;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--no-open") {
      shouldOpen = false;
      continue;
    }
    if (a === "--port") {
      const v = args[++i];
      if (!v) throw new Error("--port requires a value");
      port = Number(v);
      if (!Number.isFinite(port)) throw new Error("--port must be a number");
      continue;
    }
    if (a.startsWith("-")) {
      throw new Error(`unknown arg: ${a}`);
    }
    if (!filePath) {
      filePath = a;
      continue;
    }
    throw new Error(`unexpected extra arg: ${a}`);
  }

  return { filePath, shouldOpen, port };
}

async function readRequestBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

function sendJson(res, code, value) {
  const body = JSON.stringify(value, null, 2);
  res.statusCode = code;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.end(body);
}

function sendText(res, code, value) {
  res.statusCode = code;
  res.setHeader("content-type", "text/plain; charset=utf-8");
  res.end(String(value));
}

async function ensureParentDir(filePath) {
  const dir = path.dirname(filePath);
  await mkdir(dir, { recursive: true });
}

async function safeReadUtf8(filePath) {
  try {
    return await readFile(filePath, "utf8");
  } catch {
    return "";
  }
}

async function openBrowser(url) {
  if (process.platform === "darwin") {
    spawn("open", [url], { stdio: "ignore", detached: true }).unref();
    return;
  }
  if (process.platform === "win32") {
    spawn("cmd", ["/c", "start", "", url], { stdio: "ignore", detached: true }).unref();
    return;
  }
  spawn("xdg-open", [url], { stdio: "ignore", detached: true }).unref();
}

async function main() {
  let parsed;
  try {
    parsed = parseArgs(process.argv);
  } catch (err) {
    usage();
    console.error(String(err?.message || err));
    process.exit(2);
  }

  if (!parsed.filePath) {
    usage();
    process.exit(2);
  }

  const filePath = path.resolve(process.cwd(), parsed.filePath);
  await ensureParentDir(filePath);

  const initialText = await safeReadUtf8(filePath);

  const vite = await createViteServer({
    root: __dirname,
    server: { middlewareMode: true, hmr: false, ws: false },
    appType: "custom",
  });

  vite.middlewares.use("/api/file", (_req, res) => {
    sendJson(res, 200, { path: filePath, text: initialText });
  });

  vite.middlewares.use("/api/save", async (req, res) => {
    if (req.method !== "POST") {
      sendText(res, 405, "method not allowed");
      return;
    }
    try {
      const raw = await readRequestBody(req);
      const body = JSON.parse(raw || "{}");
      if (!body || typeof body !== "object") {
        sendText(res, 400, "invalid json body");
        return;
      }
      if (typeof body.text !== "string") {
        sendText(res, 400, "missing text");
        return;
      }
      await writeFile(filePath, body.text, "utf8");
      sendJson(res, 200, { ok: true });
    } catch (err) {
      sendText(res, 500, String(err?.message || err));
    }
  });

  // Serve the HTML shell at `/` (Vite middleware mode does not do this for us).
  vite.middlewares.use(async (req, res, next) => {
    if (req.method !== "GET") return next();
    if (req.url !== "/" && req.url !== "/index.html") return next();
    try {
      let html = await readFile(path.join(__dirname, "index.html"), "utf8");
      html = await vite.transformIndexHtml(req.url, html);
      res.statusCode = 200;
      res.setHeader("content-type", "text/html; charset=utf-8");
      res.end(html);
    } catch (err) {
      sendText(res, 500, String(err?.message || err));
    }
  });

  const httpServer = createServer(vite.middlewares);
  await new Promise((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(parsed.port, "127.0.0.1", resolve);
  });

  const address = httpServer.address();
  const actualPort = typeof address === "object" && address ? address.port : parsed.port;
  const url = `http://127.0.0.1:${actualPort}/`;

  console.log(`cm: file ${filePath}`);
  console.log(`cm: server ${url}`);
  console.log(`cm: save with Cmd+S`);
  console.log(`cm: quit with Ctrl+C`);

  if (parsed.shouldOpen) await openBrowser(url);

  const shutdown = async () => {
    await vite.close().catch(() => {});
    httpServer.close(() => process.exit(0));
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
