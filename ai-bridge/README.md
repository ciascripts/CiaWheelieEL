# AI Bridge: Claude + Codex in one room

Claude and Codex connect to the same MCP server (a Cloudflare Worker) and talk to each other in a shared room.
They discuss a task, agree who is better for it, one does the work on a new GitHub branch and opens a pull request, and the other reviews it.
You watch and steer from the **AI Bridge** iPad app, which also has a **Stop** button.

```
Claude app ──┐                       ┌── AI Bridge iPad app (watch, post, Stop)
             ├── MCP ── Worker room ─┤
ChatGPT/Codex┘      (GitHub tools)   └── GitHub (branch + pull request)
```

No API keys: both sides use your normal Claude and ChatGPT plans through custom connectors.

## What runs where
| Part | Path | Notes |
|---|---|---|
| Bridge server | `server/` | Cloudflare Worker + Durable Object. MCP at `/mcp/<key>`, app API at `/api/<key>/…` |
| iPad app | `ios/` | Built by `.github/workflows/build-ai-bridge.yml` |

The key in the URL is the password. Anyone with the URL can post in the room and use the GitHub token, so keep it private.

## One-time setup
1. **GitHub token** (lets them read code and open PRs): github.com → Settings → Developer settings → Fine-grained tokens → Generate.
   Pick only the repos they may touch. Permissions: **Contents: Read and write**, **Pull requests: Read and write**.
2. **Give the token to the bridge**: dash.cloudflare.com → Workers & Pages → **ai-bridge** → Settings → Variables and Secrets → Add → type **Secret**, name `GITHUB_TOKEN`, paste, Deploy.
3. **Claude**: claude.ai → Settings → Connectors → **Add custom connector** → name `AI Bridge`, URL = your connector URL. It then shows in the Claude iPad app too.
4. **ChatGPT / Codex**:
   - ChatGPT (web/app): Settings → Apps & Connectors → Advanced → turn on **Developer mode** → Create → URL = connector URL, authentication **None**. In a chat, turn the AI Bridge connector on.
   - Codex desktop/CLI: add to `~/.codex/config.toml`:
     ```toml
     [mcp_servers.ai_bridge]
     url = "https://…workers.dev/mcp/<key>"
     ```
     If Codex says it can't connect, update Codex. Older builds needed `experimental_use_rmcp_client = true` at the top of the file.
5. **iPad app**: sideload `AIBridge.ipa`, open Settings, paste the connector URL.

## Each task
1. In the app: ☰ → **New Task** (title + `owner/repo`).
2. ☰ → **Starter Prompts**: paste Claude's into Claude and Codex's into ChatGPT/Codex.
3. Watch them discuss, decide, work and review. Post messages to steer them.
4. If one of them pauses (each app limits how long one reply runs), type **continue** in that app.
5. Merge the pull request yourself on GitHub. **Stop** in the app blocks every tool immediately.

## Redeploy after changing the server
```sh
cd server && npm install && npx wrangler deploy
```

## Limits
- MCP can't start a reply, so each agent needs the starter prompt and occasional "continue".
- Writes only go to new branches, never the default branch; merging is always yours.
- Custom connectors may need a paid Claude or ChatGPT plan.
