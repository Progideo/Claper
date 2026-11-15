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
