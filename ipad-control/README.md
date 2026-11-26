# iPad control for Claude (MCP)

Lets Claude Desktop see your iPad screen and tap, swipe and type on it, with a floating Stop button on the iPad.

| Part | Where it runs | What it does |
|---|---|---|
| `mcp/server.py` | PC (Python) | MCP server: screenshot, tap, swipe, type, tap-by-label, Home, open app. Stop/Resume page on port 8765. |
| WebDriverAgent IPA | iPad | Does the actual screenshots and taps. Built by `.github/workflows/build-wda.yml`. |
| Claude Control IPA | iPad | Floating Picture-in-Picture window: ⏸ = Stop, ▶ = continue. Built by `.github/workflows/build-claude-control.yml`. |
| `windows/*.bat` | PC | Starts WebDriverAgent with go-ios. |

**Needs a computer:** on iPadOS 17.2, WebDriverAgent can only be started from a computer (Windows, Mac or Linux), and the MCP server runs there too.

## Setup (Windows)
1. Install Python 3, Node.js, and Apple Devices (Microsoft Store) or iTunes.
2. `npm install -g go-ios` and `pip install -r mcp\requirements.txt`.
3. Sideload `WebDriverAgent.ipa` and `ClaudeControl.ipa` with SideStore (free accounts allow 3 apps including SideStore).
4. Plug in the iPad, tap **Trust**, run `windows\find-wda.bat`, then `windows\start-ipad.bat <bundle ID>`.
   If iPad Settings → Developer shows **Enable UI Automation**, turn it on.
5. Copy `windows\claude_desktop_config.example.json` into `%APPDATA%\Claude\claude_desktop_config.json` (fix the path) and restart Claude Desktop.
6. In Claude Control on the iPad, enter the PC's IPv4 address (`ipconfig`) and tap **Show Floating Stop Button**. Allow Python through Windows Firewall when asked.

Untested on a real iPad so far: the WebDriverAgent launch with SideStore-signed builds, and the PiP Stop button.
