# 08 — Demo Script (3-Minute Walkthrough Video)

The submission requires a 3-minute walkthrough video. Three minutes is not much, and reviewers grade dozens of these. The video must be **dense, ordered, and honest** — show the platform working, show one outage being caught, show the auto-cleanup. Skip anything that doesn't move the story.

## The shape

| Beat | Wall-clock | What's on screen | What you say |
|------|-----------|------------------|--------------|
| 1 | 0:00–0:15 | Title card → terminal | "DevOps sandbox platform — a self-service mini-Heroku with chaos toggle, single VM, single command up." |
| 2 | 0:15–0:35 | `cat governance/00_INDEX.md` (just the layout fence) | "The repo is parameterised by env ID end to end — no hardcoded names, no hardcoded ports. Manifest is the source of truth." |
| 3 | 0:35–1:00 | `make up` → `docker compose ps` shows 4 platform services healthy | "One command brings up Nginx, the control API, the cleanup daemon, and the health monitor. Each runs in its own container; the daemon and monitor read state from `envs/`." |
| 4 | 1:00–1:25 | `curl -X POST localhost:18080/envs -d '{"name":"demo","ttl_minutes":5}'` → URL printed | "Create an env. The API generates a unique ID, spins a dedicated Docker network, starts the demo container with resource caps, writes a Nginx route, and returns the URL." |
| 5 | 1:25–1:45 | `curl <env-url>/health` → 200 | "The env is live. Nginx routes by env ID; each env runs on its own network." |
| 6 | 1:45–2:10 | `curl -X POST localhost:18080/envs/<id>/outage -d '{"mode":"crash"}'` → wait → `curl localhost:18080/envs` shows status `degraded` | "Crash the container. The health monitor catches it within 90 seconds and flips status to degraded. The platform itself stays up." |
| 7 | 2:10–2:30 | `curl -X POST localhost:18080/envs/<id>/outage -d '{"mode":"recover"}'` → status returns to `running` | "Recover. The simulator reads the last outage event and reverses it. Health flips back." |
| 8 | 2:30–2:45 | Show TTL ticking down, then `tail logs/cleanup.log` showing auto-destroy | "TTL expires. The cleanup daemon destroys the env: container, network, Nginx config, log archive, state file — all gone." |
| 9 | 2:45–3:00 | `make ship-check` → exits 0, then `make down` | "Every gate green. Postman pack, gitleaks, shellcheck, acceptance matrix — all checked. `make down` brings everything to a clean state." |

## Production tips

- **Pre-record `make up`.** It takes ~30s the first time; trim to ~5s in post.
- **Use a `--ttl-minutes 1` env for beat 8.** Otherwise you'll have a 5-minute gap.
- **Keep one env-ID on screen the whole demo.** Switching IDs mid-video confuses reviewers. Generate it once, reuse.
- **Show the URL in beat 4 and the same URL in beat 5.** Visual continuity matters.
- **Voice over before recording terminal.** Record audio first as a clean track; record terminal as a silent track; align in post. Trying to talk while typing always produces stumbles.
- **Captions.** Auto-caption in YouTube/Drive after upload. Reviewers grading on phones may have audio off.

## Pre-flight checklist (before hitting record)

- [ ] Repo on `main`, working tree clean.
- [ ] `.env` filled, `.env` mode is 600.
- [ ] No prior envs in `envs/`. (`make clean` if needed.)
- [ ] Terminal font size large enough to read on a 1080p video preview (minimum 16pt).
- [ ] Browser/terminal tabs not reserved for the demo are closed (no spoilers from another project).
- [ ] OBS or your screen recorder set to 1080p, 30fps, with mouse-click highlights on.
- [ ] Microphone gain checked; ambient noise minimised.
- [ ] One quick rehearsal end-to-end without recording.

## The voiceover script (full text, for read-along)

Memorise this. Three minutes is short — every word counts.

> "This is the DevOps sandbox platform — a self-service mini-Heroku with a chaos toggle, running on a single Linux VM, brought up with one command.
>
> Everything is parameterised by env ID. No hardcoded names, no hardcoded ports. The manifest at the repo root is the source of truth, and the Nginx config and Compose file are derived from it.
>
> `make up` brings up four platform services: Nginx as the front door, the control API, the cleanup daemon, and the health monitor.
>
> I create an env. The API generates a unique ID, spins a dedicated Docker network, starts the demo container with resource caps and a read-only filesystem, writes a Nginx route, reloads, and returns the URL.
>
> The env is live. Nginx routes traffic to it on its own per-env network.
>
> Now I crash it. The health monitor polls every 30 seconds; after three consecutive failures, it flips status to *degraded*. The platform stays up.
>
> Recover. The simulator reads the last outage from the event log and reverses it. The next health tick flips status back to running.
>
> TTL expires. The cleanup daemon destroys the env — container, network, Nginx config, log archive, state file. Everything is reaped.
>
> `make ship-check` runs every gate: Postman, gitleaks, shellcheck, acceptance matrix. Green. `make down` returns the host to a clean state. That's the platform."

That voice-over is 220 words. Spoken at a natural pace it lands at 2:50, leaving 10 seconds of buffer for the title card and outro card.

## The proof bundle as a fallback

If the live demo glitches during recording, fall back to `scripts/capture_evidence.sh`. It runs the same flow non-interactively and saves screenshots/logs to `evidence/<UTC ts>/`. You can edit those into the video as still frames with voice-over. Document this fallback in the README's "How the demo was produced" section.
