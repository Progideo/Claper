# NeoPro PowerPoint integration

This fork extends Claper's authenticated presenter without changing the audience
URL. Keep one enabled interaction at each position referenced from PowerPoint.
Positions are zero-based and refer to the event's Claper presentation. For
example, map the first activity to position 0 and the next activity to position 1.
Each embedded URL opens its own position and updates already connected attendees.
A reconnect does not send the initial jump again. Embedded questions remain
visible at the requested position without changing the shared results-display
setting.

## URLs

Replace `claper.example.org` with the Claper host and `CODE` with an event code.

| Use | Example |
| --- | --- |
| Project an event at a specific position | `https://claper.example.org/e/CODE/presenter?iframe=1&goto=1` |
| Project the trainer's event for a course | `https://claper.example.org/c/istqb-ctal-testeur-agile-v2-0/presenter?iframe=1&goto=1` |
| Open the manager for the same course | `https://claper.example.org/c/istqb-ctal-testeur-agile-v2-0/manage` |
| Show the course event's QR code | `https://claper.example.org/c/istqb-ctal-testeur-agile-v2-0/presenter?iframe=1&screen=join` |

## Prepare a shared session

1. Keep the template named exactly like the catalog course, for example
   `ISTQB CTAL Testeur Agile v2.0`. The course URL segment is the lowercase,
   accent-free catalog name with punctuation and whitespace collapsed to hyphens.
2. From the template owner's account, duplicate the template for each session.
   Keep Claper's ` (Copy)` suffix or use a session suffix, for example
   `ISTQB CTAL Testeur Agile v2.0 – Lyon 20/11`. Keep the catalog name short
   enough for Claper to retain it on duplication.
3. In the copy's event settings, add the trainer as a facilitator with the
   email address on their Claper account. Assign each trainer to their own copy
   for concurrent sessions.
4. The trainer signs in with their own account and opens the PowerPoint.

Course URLs consider unexpired events owned or facilitated by the signed-in
user. The normalized event name must start with the course segment. An exact
match identifies the template and is excluded, even for its owner. Use distinct
course prefixes where courses can overlap. When several sessions match, Claper
selects the latest `started_at`, then the latest `inserted_at`, then the
highest event ID if both timestamps are equal.

The embedded QR screen uses the attendee URL and leaves the shared page and
visibility settings alone. The `screen=join` option takes priority over `goto`
when embedded.

## Build and publish

```sh
docker build -t claper-neopro:local .
```

Use the existing Claper environment variables. The repository's GitHub Actions
workflow builds the Dockerfile after the test job on version tags matching
`v*`, then publishes AMD64 and ARM64 images to
`ghcr.io/progideo/claper:<version-tag>`. Enable Actions on the fork and use its
`GITHUB_TOKEN` with package write permissions. Example tag for a verified
release on the Claper 3.3.0 base:

```sh
git tag -a v3.3.0-neopro.1 -m "NeoPro release based on Claper 3.3.0"
git push origin refs/tags/v3.3.0-neopro.1
```

## Update Claper

Fetch an upstream release tag from `https://github.com/ClaperCo/Claper.git`.
Create an update branch from that tag and replay the NeoPro commits in order.
Review facilitator permissions, course-session resolution and session return
URLs, presentation state and both PubSub messages, the LiveView hook lifecycle,
and presenter markup and styling.
Run `mix format --check-formatted`, `mix test` on a disposable test database and
`docker build`. Check an embedded question, a socket reconnect, the QR code and
the standard presenter in PowerPoint or a browser before tagging the image.

## Modified upstream files

- `.github/workflows/elixir.yml`
- `assets/js/app.js`
- `assets/js/presenter.js`
- `lib/claper/events.ex`
- `lib/claper/presentations.ex`
- `lib/claper_web/live/event_live/manage.ex`
- `lib/claper_web/live/event_live/presenter.ex`
- `lib/claper_web/live/event_live/presenter.html.heex`
- `lib/claper_web/router.ex`
- Gettext catalogs for the course error page

Manrope is served locally. Its font files are distributed under the bundled
SIL Open Font License. Claper and the NeoPro changes are distributed under the
repository's AGPL-3.0 license.
