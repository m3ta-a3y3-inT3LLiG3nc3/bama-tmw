# Reaching the Mac from iPhone / iPad / Watch (NOT ENABLED — needs Kingdom's OK)
The sidecar stays on 127.0.0.1:9782/9783. No 0.0.0.0, no Funnel, no public exposure.
The proposed safe path is tailnet-only HTTPS through Tailscale Serve. Run it on the Mac only after Kingdom says OK:
    tailscale serve --bg --set-path /jarvis http://127.0.0.1:9782
    tailscale serve --bg --set-path /rea    http://127.0.0.1:9783
Undo: `tailscale serve reset`. Never use `tailscale funnel`.
Then, in the app's Settings, enter the Mac's MagicDNS name (`<mac>.<tailnet>.ts.net`). The app accepts only *.ts.net names.
Remote approvals also need two new 9782 routes: GET /api/jev/pending and POST /api/jev/decide (see ConsoleCore/Remote.swift).
Adding them needs Kingdom's OK and a 9782 restart. Until then, the devices show demo data.
