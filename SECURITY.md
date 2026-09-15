# Security

AirPoise is designed so there is almost nothing to leak.

- **No network.** The app does not open sockets, talk to a server, or ship analytics.
- **No account.** There is no login, token, or cloud sync.
- **Local files only.** Settings and daily stats live in `~/Library/Application Support/AirPoise/`.
- **Permissions stay optional.** Accessibility, AppleScript, and shell run only when you bind a gesture to them.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for a security problem.

Email **jaskirat880singh@gmail.com** with:

- what you found
- how to reproduce it
- affected version / commit

I will reply and patch before anything is disclosed.

## What this repo should never contain

- `.env`, API keys, tokens, certificates, `.p12`, `.pem`
- The marketing site (`site/` is gitignored on purpose)
- Real user `settings.json` / `stats.json` from Application Support
