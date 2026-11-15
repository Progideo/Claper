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

### Returning to a PowerPoint activity

PowerPoint for Mac 16.112.4 kept the three diagnostic frames loaded between
slides. Each measured return produced `visibilitychange` with a state of
`visible`. Focus stayed false, intersection events appeared only on first
display, and timer delays continued in hidden frames.

An embedded presenter with a valid `goto` applies its position on first display
and again on a hidden-to-visible transition. It waits 150 ms on return and checks
that the presenter intersects the viewport before sending a single LiveView
event. Hiding or disconnecting the frame cancels pending work. A reconnect
retries only a pending activation while visible. The server uses the position
from the URL, checks the current presenter permissions and broadcasts only if
the shared position changes.

This uses the existing PowerPoint URLs and add-in. It avoids reloading the
content or using periodic requests from frames that PowerPoint keeps alive.
Windows and PowerPoint for the web can report document visibility differently.
If the host keeps an off-screen frame both visible and intersecting, these
signals cannot distinguish it from the slide on screen. If a host does not emit
visibility changes between slides, use the diagnostic journal before choosing
an alternative signal from the add-in.

To verify in PowerPoint, sign in as a presenter and open the same event as an
attendee on another device or browser profile. Present slide 6 (`goto=0`),
then slide 12 (`goto=1`), return to 6 and go to 12 again. The attendee should
see positions 0 → 1 → 0 → 1. Rapidly skip past one activity, then stop on the
other and confirm that the final question stays active. Open a `screen=join`
slide and confirm that it shows the QR code without changing the attendee's
question.

## Performance

An embedded presenter loads the current slide, the Claper JavaScript and styles,
and Manrope. A valid `goto` selects the initial image directly. LiveView
replaces that image as the shared position changes. The embedded join screen
loads the QR code without presentation images. The regular presenter keeps its
full slide carousel.

The production build generates fingerprinted assets with Phoenix. URLs ending
in `?vsn=d` carry a one-year browser cache with `immutable`. The same policy
applies to numbered JPG slides under `/uploads/<hash>/` because a new conversion
uses a new path. Thumbnails and ordinary asset URLs retain ETag revalidation.
A cached slide remains usable until its cache entry expires or is cleared.
Leave cache headers for S3-hosted presentations to the S3 or CDN configuration.

Plug serves precompressed gzip assets from `phx.digest`. The Docker builder also
precompresses JavaScript, CSS and TrueType fonts with the Brotli command-line
tool. Plug serves the Brotli variant when the browser accepts it, with gzip as a
fallback. This uses no additional dependency in the running container.

When a course session cannot be resolved, the page shows the signed-in email.
**Switch account** clears that Claper session and returns to the same course URL
and query string after sign-in.

For example, add the cache zone to nginx's `http` block and the location to the
existing Claper virtual host. Keep application routes and the LiveView WebSocket
on the existing proxy configuration. Substitute the address of the Claper
upstream if it runs on a different host or port.

```nginx
# In http:
proxy_cache_path /var/cache/nginx/claper levels=1:2 keys_zone=claper_static:10m
                 max_size=1g inactive=7d use_temp_path=off;

# In the Claper server block:
location ~ ^/(assets|fonts|uploads)/ {
    proxy_pass http://127.0.0.1:4000;
    proxy_set_header Host $host;
    proxy_set_header Accept-Encoding $http_accept_encoding;
    proxy_cache claper_static;
    proxy_cache_lock on;
    gzip on;
    gzip_vary on;
    gzip_types application/javascript text/javascript text/css font/ttf;
}
```

The proxy respects the origin's freshness and encoding headers. Include the
query string in the cache key and preserve `Vary: Accept-Encoding` when adapting
this example.

## Slideshow diagnostics

Set `NEOPRO_DIAG_TOKEN` in the Claper app environment and restart the app to
enable the probe. Generate a short-lived URL-safe secret with
`openssl rand -hex 32`. Keep it private. The diagnostic URLs contain this
token and may appear in HTTP access logs. Keep the diagnostic PowerPoint
private and rotate or remove the token after the run. The endpoints return 404 when the token is unset or wrong.
The probe sends observations with a Bearer header and uses no app assets or
external services.

1. Put three Live Website Viewer frames on three slides. Set their URLs to
   `https://claper.example.org/neopro/diag?label=A&token=TOKEN`,
   `https://claper.example.org/neopro/diag?label=B&token=TOKEN`, and
   `https://claper.example.org/neopro/diag?label=C&token=TOKEN`. Substitute
   the same secret in all three URLs.
2. In Slideshow mode, note the platform, Office version, and UTC start time.
   Navigate A → B → C → A → C. Wait at least two seconds at each stop, and
   repeat without clicking inside the frames. Note the times of the transitions.
3. Open `https://claper.example.org/neopro/diag/log?token=TOKEN` in a browser
   after the run. Capture the rows for the selected time range. The log shows
   server receipt times in UTC, latest first. The short instance identifier
   before each detail helps distinguish a resumed frame from a fresh load of
   the same label.

The probe records visibility, focus, page lifecycle, window and document
sizes, and intersection changes. It records animation pauses longer than one
second and timer delays over 250 ms. Message observations record origin, sender
category and a bounded summary of the message type. Message bodies are omitted.
The server keeps 1,000 observations per app instance in RAM, up to 2 KiB per
request and 180 submissions per 10 seconds. A restart clears the log.

Test the same slide sequence on Mac, Windows, and PowerPoint for the web.
Desktop hosts can suspend an embedded browser or keep an off-screen frame
running. Focus can also change when the presenter clicks the slide. On the web,
tab visibility and an individual iframe's visibility can differ. Compare the
recorded signals with the noted slide transitions before choosing a signal.

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
- `Dockerfile`
- `config/runtime.exs`
- `lib/claper/application.ex`
- `lib/claper/events.ex`
- `lib/claper/presentations.ex`
- `lib/claper_web/live/event_live/manage.ex`
- `lib/claper_web/live/event_live/presenter.ex`
- `lib/claper_web/live/event_live/presenter.html.heex`
- `lib/claper_web/controllers/user_auth.ex`
- `lib/claper_web/endpoint.ex`
- `lib/claper_web/router.ex`
- `lib/claper_web/templates/layout/{admin,root,user}.html.heex`
- Gettext catalogs for the course error page

Manrope is served locally. Its font files are distributed under the bundled
SIL Open Font License. Claper and the NeoPro changes are distributed under the
repository's AGPL-3.0 license.
