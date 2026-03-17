# Windows Cloud Deployment

This project can run without Codex after it is deployed to an always-on Windows server.

## Recommended architecture

- Windows Server 2019 or 2022 x64 VM with RDP access
- One dedicated QQ account only for this bot
- One always-on interactive Windows session for that account
- NapCat bound to `127.0.0.1` only
- Daily sender triggered by Windows Task Scheduler at 08:30 Asia/Shanghai

Why this shape:

- The current sender uses `QQ.exe` plus the Windows NapCat shell.
- QQ and NapCat need an interactive Windows user session.
- A normal background service model is not enough for this stack.

## Prerequisites

Install these on the cloud host first:

1. QQ for Windows
2. Node.js 20+
3. Git

Clone the repo, then create `.env` from `.env.example`.

Required values:

- `LLM_PROVIDER=deepseek`
- `DEEPSEEK_API_KEY=...`
- `QQ_GROUP_ID=468528719`

Optional but recommended:

- `CLOUD_DAILY_TIME=08:30`
- `QQ_API_BASE_URL=http://127.0.0.1:3000`

## Bootstrap

Run this from the project root:

```powershell
npm.cmd run cloud:bootstrap
```

What it does:

- installs Node dependencies with `npm ci`
- downloads the latest `NapCat.Shell.zip`
- writes `webui.json` and `onebot11.json`
- pins NapCat to the locally installed QQ version
- registers one scheduled task for the current Windows user

Tasks created:

- `MilitaryDigest Daily Digest`

## First login

After bootstrap, run:

```powershell
npm.cmd run qq:status
```

If QQ is not logged in yet, the script opens the local QR image and prints the QR link.

After the QR scan succeeds, you should see:

```text
QQ login: OK
OneBot HTTP (3000): OK
```

## Auto-logon

To survive reboots, configure the Windows account used for the bot to log on automatically at the console.

Recommended tool:

- Sysinternals Autologon

After auto-logon is enabled:

- the machine reboots
- Windows logs that user in automatically
- `MilitaryDigest Daily Digest` runs every day at the scheduled time
- the daily task starts QQ and NapCat on demand when it needs to send

## RDP usage

Do not sign out the bot account after setup.

Use disconnect instead of sign out when closing RDP. Signing out ends the interactive session that QQ depends on.

## Recovery

If QQ login expires:

```powershell
npm.cmd run qq:status
```

Scan the QR code again.

If QQ updates and NapCat stops working:

```powershell
npm.cmd run napcat:install
```

If you need to recreate scheduled tasks:

```powershell
npm.cmd run cloud:unregister
npm.cmd run cloud:register
```

## Security notes

- Keep `QQ_API_BASE_URL` on `127.0.0.1`.
- Keep NapCat WebUI on `127.0.0.1`.
- Do not expose ports `3000` or `6099` directly to the public internet.
- Use a dedicated QQ account, not your main personal account.
