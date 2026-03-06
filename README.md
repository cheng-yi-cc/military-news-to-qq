# Military And Geopolitics Digest To QQ Group

This project does four things on each run:

1. Fetch candidate stories from international and defense RSS feeds.
2. Filter out weak matches with rule-based relevance scoring.
3. Use OpenAI or DeepSeek to choose the top 5 most impactful stories and write Chinese summaries.
4. Send the final digest to a QQ group through a OneBot or NapCat HTTP endpoint.

## Requirements

- Node.js 20+
- Either `OPENAI_API_KEY` or `DEEPSEEK_API_KEY`
- A QQ bot HTTP endpoint that can send group messages
  - Recommended: NapCatQQ or another OneBot v11 compatible sender
  - Default path: `POST /send_group_msg`

## Setup

Copy the env template:

```powershell
Copy-Item .env.example .env
```

Required QQ fields:

- `QQ_API_BASE_URL`
- `QQ_GROUP_ID`

Choose one LLM provider:

- OpenAI
  - `LLM_PROVIDER=openai`
  - `OPENAI_API_KEY`
- DeepSeek
  - `LLM_PROVIDER=deepseek`
  - `DEEPSEEK_API_KEY`

Optional QQ auth:

- `QQ_API_ACCESS_TOKEN`

Optional custom send path:

- `QQ_SEND_GROUP_PATH`

## Commands

Preview ranked candidates without calling the LLM or QQ:

```powershell
npm.cmd run preview
```

Build the final digest but only print it locally:

```powershell
npm.cmd run dry-run
```

Send to QQ:

```powershell
npm.cmd run run
```

Check QQ login status and show the current QR link when login is still pending:

```powershell
npm.cmd run qq:status
```

Run the full Windows daily entrypoint with NapCat startup and login diagnostics:

```powershell
npm.cmd run daily
```

Force a same-day resend:

```powershell
node .\src\index.mjs --force
```

## NapCat Notes

- `scripts\start-napcat.ps1` automatically stages NapCat into `%LOCALAPPDATA%\CodexNapCatQQ` before launch. This avoids startup failures caused by workspace paths that contain spaces or non-ASCII characters.
- The first run still requires a manual QQ login. If `scripts\run-daily.ps1` reports that QQ login is required, scan the QR code shown in the QQ window or use the QR link printed by the script.
- After QQ is logged in successfully, NapCat should expose:
  - WebUI: `http://127.0.0.1:6099`
  - OneBot HTTP: `http://127.0.0.1:3000`

## State

Send history is stored in:

`data/state.json`

It prevents duplicate daily sends and avoids resending recently delivered links.
