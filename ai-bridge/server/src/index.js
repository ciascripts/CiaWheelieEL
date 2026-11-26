// AI Bridge: a shared room where Claude and Codex talk, decide who does a task,
// and work on GitHub. Both connect to this Worker as an MCP server (Streamable
// HTTP, no OAuth: the secret key in the URL is the password). The iPad app uses
// the small REST API under /api/<key>/.
//
//   MCP endpoint:  https://<worker>/mcp/<BRIDGE_KEY>
//   App API:       https://<worker>/api/<BRIDGE_KEY>/state  (and /message, /task, /stop, /resume, /clear)

const SERVER_INFO = { name: "ai-bridge", version: "1.0.0" };
const PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];
const AGENTS = ["claude", "codex"];
const KINDS = ["message", "proposal", "decision", "work", "review", "done"];
const MAX_MESSAGES = 400;
const WAIT_MAX_SECONDS = 45;

const INSTRUCTIONS = `You are in a shared room with another AI coding agent (Claude or Codex) and the human owner.
Workflow for each task:
1. Call bridge_join with your name to get the task and recent messages.
2. Discuss: post a short proposal (kind "proposal") saying which of you is better suited and why, with a plan.
3. Agree. One of you posts kind "decision" naming who does the work. If you disagree twice, the human decides.
4. The assignee works on GitHub: a new branch (never the default branch), commits with github_write_file, then github_open_pr. Post short "work" updates.
5. The other agent reviews with github_pr_diff and posts kind "review" (approve or list concrete fixes).
6. When the review passes, post kind "done". The human merges the PR.
Between steps call bridge_wait to wait for the other agent; if it times out, call it again.
Keep messages short. Follow anything the human ("you") posts. If a tool says STOPPED, stop and tell the user.`;

// ---------------------------------------------------------------- Worker entry

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
    const parts = url.pathname.split("/").filter(Boolean); // ["mcp", key] or ["api", key, action]
    if (parts.length === 0) return text("AI Bridge is running.");
    const [area, key, ...rest] = parts;
    if (!env.BRIDGE_KEY || !key || !safeEqual(key, env.BRIDGE_KEY)) {
      return cors(json({ error: "unknown bridge" }, 404));
    }
    const room = env.ROOM.get(env.ROOM.idFromName("main"));
    if (area === "mcp") return cors(await handleMcp(request, env, room));
    if (area === "api") {
      const forwarded = new Request(`https://room/${rest.join("/")}${url.search}`, request);
      return cors(await room.fetch(forwarded));
    }
    return cors(json({ error: "not found" }, 404));
  },
};

// ------------------------------------------------------------------------- MCP

async function handleMcp(request, env, room) {
  if (request.method === "GET" || request.method === "DELETE") {
    return new Response("Method Not Allowed", { status: 405, headers: { Allow: "POST" } });
  }
  if (request.method !== "POST") return json({ error: "POST only" }, 405);
  let body;
  try {
    body = await request.json();
  } catch {
    return json(rpcError(null, -32700, "Parse error"), 400);
  }
  const batch = Array.isArray(body) ? body : [body];
  const replies = [];
  for (const msg of batch) {
    const reply = await handleRpc(msg, env, room);
    if (reply) replies.push(reply);
  }
  if (replies.length === 0) return new Response(null, { status: 202 });
  return json(Array.isArray(body) ? replies : replies[0]);
}

async function handleRpc(msg, env, room) {
  const isNotification = msg.id === undefined || msg.id === null;
  try {
    let result;
    switch (msg.method) {
      case "initialize": {
        const asked = msg.params?.protocolVersion;
        result = {
          protocolVersion: PROTOCOL_VERSIONS.includes(asked) ? asked : PROTOCOL_VERSIONS[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo: SERVER_INFO,
          instructions: INSTRUCTIONS,
        };
        break;
      }
      case "ping":
        result = {};
        break;
      case "tools/list":
        result = { tools: TOOLS.map(({ handler, ...t }) => t) };
        break;
      case "tools/call": {
        const tool = TOOLS.find((t) => t.name === msg.params?.name);
        if (!tool) return rpcError(msg.id, -32602, `Unknown tool: ${msg.params?.name}`);
        result = await callTool(tool, msg.params?.arguments || {}, env, room);
        break;
      }
      default:
        if (isNotification) return null; // notifications/initialized etc.
        return rpcError(msg.id, -32601, `Method not found: ${msg.method}`);
    }
    return isNotification ? null : { jsonrpc: "2.0", id: msg.id, result };
  } catch (e) {
    return isNotification ? null : rpcError(msg.id, -32603, String(e?.message || e));
  }
}

async function callTool(tool, args, env, room) {
  try {
    const state = await roomCall(room, "GET", "state?since=999999999");
    if (state.stopped && tool.name !== "bridge_join") {
      return toolText("STOPPED: the human pressed Stop in the Bridge app. Do not continue or retry. Tell the user you have stopped.", true);
    }
    const out = await tool.handler(args, env, room);
    return toolText(typeof out === "string" ? out : JSON.stringify(out, null, 2));
  } catch (e) {
    return toolText(`Error: ${e?.message || e}`, true);
  }
}

const toolText = (text, isError = false) => ({ content: [{ type: "text", text }], ...(isError ? { isError: true } : {}) });
const rpcError = (id, code, message) => ({ jsonrpc: "2.0", id, error: { code, message } });

function agentArg(args) {
  const agent = String(args.agent || "").toLowerCase();
  if (!AGENTS.includes(agent)) throw new Error(`agent must be "claude" or "codex"`);
  return agent;
}

const agentProp = { type: "string", enum: AGENTS, description: 'Who you are: "claude" or "codex".' };
const repoProp = { type: "string", description: 'GitHub repo as "owner/name".' };

const TOOLS = [
  {
    name: "bridge_join",
    description: "Join the room. Returns the current task, how the room works, and recent messages. Call this first.",
    inputSchema: { type: "object", properties: { agent: agentProp }, required: ["agent"] },
    handler: async (args, env, room) => {
      const agent = agentArg(args);
      await roomCall(room, "POST", "presence", { agent });
      const state = await roomCall(room, "GET", "state?since=0");
      return {
        you: agent,
        other_agent: agent === "claude" ? "codex" : "claude",
        stopped: state.stopped,
        task: state.task,
        how_it_works: INSTRUCTIONS,
        recent_messages: state.messages.slice(-25),
        last_message_id: state.lastId,
      };
    },
  },
  {
    name: "bridge_post",
    description: `Post a message to the room. kind: ${KINDS.join(", ")}. Use "decision" to say who does the task.`,
    inputSchema: {
      type: "object",
      properties: {
        agent: agentProp,
        text: { type: "string", description: "The message. Keep it short." },
        kind: { type: "string", enum: KINDS, description: "Defaults to message." },
        assignee: { type: "string", enum: AGENTS, description: 'With kind "decision": who does the work.' },
      },
      required: ["agent", "text"],
    },
    handler: async (args, env, room) => {
      const agent = agentArg(args);
      const kind = KINDS.includes(args.kind) ? args.kind : "message";
      const msg = await roomCall(room, "POST", "post", { from: agent, kind, text: String(args.text || ""), assignee: args.assignee });
      return { posted: msg.id };
    },
  },
  {
    name: "bridge_wait",
    description: `Wait up to ${WAIT_MAX_SECONDS}s for new messages from the other agent or the human after since_id. Returns them, or "no new messages" so you can call again.`,
    inputSchema: {
      type: "object",
      properties: {
        agent: agentProp,
        since_id: { type: "integer", description: "Last message id you have seen." },
        seconds: { type: "integer", description: `Max wait, up to ${WAIT_MAX_SECONDS}.` },
      },
      required: ["agent", "since_id"],
    },
    handler: async (args, env, room) => {
      const agent = agentArg(args);
      const seconds = Math.max(1, Math.min(WAIT_MAX_SECONDS, Number(args.seconds) || WAIT_MAX_SECONDS));
      const res = await roomCall(room, "GET", `wait?agent=${agent}&since=${Number(args.since_id) || 0}&seconds=${seconds}`);
      if (res.stopped) return "STOPPED: the human pressed Stop. Do not continue.";
      if (!res.messages.length) return { messages: [], last_message_id: res.lastId, note: "No new messages yet. Call bridge_wait again." };
      return { messages: res.messages, last_message_id: res.lastId, task: res.task };
    },
  },
  {
    name: "github_tree",
    description: "List every file path in a repo branch (truncated to 600).",
    inputSchema: { type: "object", properties: { repo: repoProp, ref: { type: "string", description: "Branch; default branch if empty." } }, required: ["repo"] },
    handler: async (args, env) => {
      const ref = args.ref || (await defaultBranch(env, args.repo));
      const tree = await gh(env, `/repos/${args.repo}/git/trees/${encodeURIComponent(ref)}?recursive=1`);
      const files = (tree.tree || []).filter((t) => t.type === "blob").map((t) => t.path);
      return { ref, count: files.length, files: files.slice(0, 600), truncated: files.length > 600 || !!tree.truncated };
    },
  },
  {
    name: "github_read_file",
    description: "Read a text file from a repo.",
    inputSchema: { type: "object", properties: { repo: repoProp, path: { type: "string" }, ref: { type: "string" } }, required: ["repo", "path"] },
    handler: async (args, env) => {
      const q = args.ref ? `?ref=${encodeURIComponent(args.ref)}` : "";
      const file = await gh(env, `/repos/${args.repo}/contents/${encodePath(args.path)}${q}`);
      if (Array.isArray(file)) return { directory: file.map((f) => `${f.type === "dir" ? "📁" : "📄"} ${f.path}`) };
      const content = decodeBase64Utf8(file.content || "");
      return content.length > 60000 ? content.slice(0, 60000) + "\n…(truncated)" : content;
    },
  },
  {
    name: "github_write_file",
    description: "Create or replace a file on a work branch (created from the default branch if missing). Never writes to the default branch.",
    inputSchema: {
      type: "object",
      properties: {
        agent: agentProp,
        repo: repoProp,
        branch: { type: "string", description: 'Work branch, e.g. "bridge/fix-login".' },
        path: { type: "string" },
        content: { type: "string", description: "Full new file content." },
        message: { type: "string", description: "Commit message." },
      },
      required: ["agent", "repo", "branch", "path", "content", "message"],
    },
    handler: async (args, env, room) => {
      const agent = agentArg(args);
      const base = await defaultBranch(env, args.repo);
      if (args.branch === base) throw new Error(`Won't write to the default branch (${base}). Use a work branch.`);
      await ensureBranch(env, args.repo, args.branch, base);
      let sha;
      try {
        const existing = await gh(env, `/repos/${args.repo}/contents/${encodePath(args.path)}?ref=${encodeURIComponent(args.branch)}`);
        sha = existing.sha;
      } catch (e) {
        if (!String(e.message).includes("404")) throw e;
      }
      const res = await gh(env, `/repos/${args.repo}/contents/${encodePath(args.path)}`, {
        method: "PUT",
        body: { message: `${args.message}\n\nCommitted by ${agent} via AI Bridge`, content: encodeBase64Utf8(args.content), branch: args.branch, ...(sha ? { sha } : {}) },
      });
      await roomCall(room, "POST", "post", { from: agent, kind: "work", text: `Committed ${args.path} on ${args.branch}`, auto: true });
      return { committed: res.commit?.sha, path: args.path, branch: args.branch };
    },
  },
  {
    name: "github_open_pr",
    description: "Open a pull request from a work branch into the default branch.",
    inputSchema: {
      type: "object",
      properties: { agent: agentProp, repo: repoProp, branch: { type: "string" }, title: { type: "string" }, body: { type: "string" } },
      required: ["agent", "repo", "branch", "title"],
    },
    handler: async (args, env, room) => {
      const agent = agentArg(args);
      const base = await defaultBranch(env, args.repo);
      const pr = await gh(env, `/repos/${args.repo}/pulls`, {
        method: "POST",
        body: { title: args.title, head: args.branch, base, body: `${args.body || ""}\n\n_Opened by ${agent} via AI Bridge._` },
      });
      await roomCall(room, "POST", "post", { from: agent, kind: "work", text: `Opened PR #${pr.number}: ${pr.title}\n${pr.html_url}`, auto: true, link: pr.html_url });
      return { number: pr.number, url: pr.html_url };
    },
  },
  {
    name: "github_pr_diff",
    description: "Get a pull request's diff (for reviewing).",
    inputSchema: { type: "object", properties: { repo: repoProp, number: { type: "integer" } }, required: ["repo", "number"] },
    handler: async (args, env) => {
      const diff = await gh(env, `/repos/${args.repo}/pulls/${Number(args.number)}`, { accept: "application/vnd.github.diff" });
      return diff.length > 80000 ? diff.slice(0, 80000) + "\n…(truncated)" : diff;
    },
  },
];

// ---------------------------------------------------------------------- GitHub

async function gh(env, path, { method = "GET", body, accept = "application/vnd.github+json" } = {}) {
  if (!env.GITHUB_TOKEN) throw new Error("No GitHub token set on the bridge. Add GITHUB_TOKEN in the Cloudflare dashboard.");
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: accept,
      "User-Agent": "ai-bridge",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`GitHub ${res.status} on ${method} ${path}: ${raw.slice(0, 300)}`);
  if (accept !== "application/vnd.github+json") return raw;
  return raw ? JSON.parse(raw) : {};
}

async function defaultBranch(env, repo) {
  return (await gh(env, `/repos/${repo}`)).default_branch;
}

async function ensureBranch(env, repo, branch, base) {
  try {
    await gh(env, `/repos/${repo}/git/ref/heads/${encodeURIComponent(branch)}`);
    return;
  } catch (e) {
    if (!String(e.message).includes("404")) throw e;
  }
  const baseRef = await gh(env, `/repos/${repo}/git/ref/heads/${encodeURIComponent(base)}`);
  await gh(env, `/repos/${repo}/git/refs`, { method: "POST", body: { ref: `refs/heads/${branch}`, sha: baseRef.object.sha } });
}

const encodePath = (p) => String(p).split("/").map(encodeURIComponent).join("/");

function decodeBase64Utf8(b64) {
  const bin = atob(b64.replace(/\s/g, ""));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

function encodeBase64Utf8(text) {
  const bytes = new TextEncoder().encode(text);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

// ------------------------------------------------------------------------ Room

async function roomCall(room, method, path, body) {
  const res = await room.fetch(`https://room/${path}`, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || `room error ${res.status}`);
  return data;
}

export class Room {
  constructor(ctx) {
    this.ctx = ctx;
    this.waiters = new Set();
    this.loaded = this.ctx.blockConcurrencyWhile(async () => {
      this.messages = (await this.ctx.storage.get("messages")) || [];
      this.nextId = (await this.ctx.storage.get("nextId")) || 1;
      this.task = (await this.ctx.storage.get("task")) || null;
      this.stopped = (await this.ctx.storage.get("stopped")) || false;
      this.presence = (await this.ctx.storage.get("presence")) || {};
    });
  }

  snapshot(since = 0) {
    return {
      messages: this.messages.filter((m) => m.id > since),
      lastId: this.nextId - 1,
      task: this.task,
      stopped: this.stopped,
      presence: this.presence,
    };
  }

  async add(from, kind, text, extra = {}) {
    const msg = { id: this.nextId++, from, kind, text: String(text).slice(0, 8000), ts: Date.now(), ...extra };
    this.messages.push(msg);
    if (this.messages.length > MAX_MESSAGES) this.messages = this.messages.slice(-MAX_MESSAGES);
    await this.ctx.storage.put({ messages: this.messages, nextId: this.nextId });
    for (const wake of this.waiters) wake();
    return msg;
  }

  async fetch(request) {
    await this.loaded;
    const url = new URL(request.url);
    const route = url.pathname.replace(/^\/+/, "");
    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {};
    const since = Number(url.searchParams.get("since")) || 0;

    switch (route) {
      case "state":
        return json(this.snapshot(since));

      case "wait": {
        const agent = url.searchParams.get("agent");
        const seconds = Math.min(WAIT_MAX_SECONDS, Number(url.searchParams.get("seconds")) || WAIT_MAX_SECONDS);
        const fresh = () => this.messages.filter((m) => m.id > since && m.from !== agent);
        if (!fresh().length && !this.stopped) {
          await new Promise((resolve) => {
            const wake = () => {
              if (fresh().length || this.stopped) done();
            };
            const done = () => {
              clearTimeout(timer);
              this.waiters.delete(wake);
              resolve();
            };
            const timer = setTimeout(done, seconds * 1000);
            this.waiters.add(wake);
          });
        }
        return json({ messages: fresh(), lastId: this.nextId - 1, task: this.task, stopped: this.stopped });
      }

      case "post": {
        const from = AGENTS.includes(body.from) ? body.from : "you";
        const kind = KINDS.includes(body.kind) ? body.kind : "message";
        const extra = {};
        if (kind === "decision" && AGENTS.includes(body.assignee)) {
          extra.assignee = body.assignee;
          if (this.task) {
            this.task.assignee = body.assignee;
            await this.ctx.storage.put("task", this.task);
          }
        }
        if (body.link) extra.link = String(body.link);
        if (body.auto) extra.auto = true;
        if (kind === "done" && this.task) {
          this.task.status = "done";
          await this.ctx.storage.put("task", this.task);
        }
        return json(await this.add(from, kind, body.text || "", extra));
      }

      case "presence": {
        if (AGENTS.includes(body.agent)) {
          this.presence[body.agent] = Date.now();
          await this.ctx.storage.put("presence", this.presence);
          await this.add("system", "message", `${body.agent === "claude" ? "Claude" : "Codex"} joined`);
        }
        return json({ ok: true });
      }

      // ---- used by the iPad app
      case "message":
        return json(await this.add("you", "message", body.text || ""));

      case "task": {
        this.task = {
          title: String(body.title || "Untitled task").slice(0, 200),
          repo: String(body.repo || ""),
          details: String(body.details || "").slice(0, 4000),
          assignee: null,
          status: "open",
          created: Date.now(),
        };
        await this.ctx.storage.put("task", this.task);
        await this.add("system", "message", `New task: ${this.task.title}${this.task.repo ? ` (${this.task.repo})` : ""}`);
        return json(this.snapshot(since));
      }

      case "stop":
      case "resume": {
        this.stopped = route === "stop";
        await this.ctx.storage.put("stopped", this.stopped);
        await this.add("system", "message", this.stopped ? "■ Stopped by you" : "▶ Resumed by you");
        return json(this.snapshot(since));
      }

      case "clear": {
        this.messages = [];
        this.task = null;
        await this.ctx.storage.put({ messages: [], task: null });
        await this.add("system", "message", "Room cleared");
        return json(this.snapshot(0));
      }

      default:
        return json({ error: "not found" }, 404);
    }
  }
}

// --------------------------------------------------------------------- helpers

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}

function text(body, status = 200) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain" } });
}

function cors(res) {
  const r = new Response(res.body, res);
  r.headers.set("Access-Control-Allow-Origin", "*");
  r.headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  r.headers.set("Access-Control-Allow-Headers", "Content-Type, Mcp-Session-Id, MCP-Protocol-Version, Authorization");
  return r;
}

function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
