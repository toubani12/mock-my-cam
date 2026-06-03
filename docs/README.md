# MockMyCam landing page

A single static page (`index.html`) — no build step, no dependencies. Theme: *"islands in a
dawn sky"* — a light, glass-panel ("floating islands") look with hand-authored CSS. Fonts are
**self-hosted** as `woff2` in `assets/fonts/` (**Fraunces** display serif, **Hanken Grotesk**
body, **Spline Sans Mono** for code) — no Google Fonts CDN, so the page makes **zero
third-party requests** (GDPR-friendly: no visitor IP is sent to Google). Just open the file or
host the folder.

The page is SEO-optimized: a keyword-tuned `<title>` / meta description (targeting *"virtual
camera for the iOS Simulator"*), Open Graph + Twitter cards, `SoftwareApplication` + `FAQPage`
JSON-LD structured data, a `<link rel="canonical">`, an SVG favicon, a visible FAQ section, and
`robots.txt` + `sitemap.xml` served alongside it.

## Preview locally

```bash
# from the repo root
python3 -m http.server -d docs 8000
# → http://localhost:8000
```

(Or simply open `docs/index.html` in a browser.)

## Publish

The site is plain static files — `index.html`, the `assets/` folder, plus `robots.txt` and
`sitemap.xml`. Host it anywhere.

**On your own server (aaPanel etc.)** — production home: **https://mockmycam.kaarlmoroti.com/**
Upload `index.html`, `privacy.html`, the `assets/` folder, `robots.txt`, and `sitemap.xml` into
the site's document root (e.g. `/www/wwwroot/<site>/`), keeping them side by side (the pages use
relative `assets/…` paths). Re-build the bundle with
`cd docs && zip -r ../mockmycam-site.zip index.html privacy.html assets robots.txt sitemap.xml -x '*.DS_Store' '*.gitkeep'`,
then upload that `mockmycam-site.zip` (repo root, git-ignored) and unzip in place.

**GitHub Pages (free alternative)** — Settings → Pages → *Deploy from a branch*, Branch `main`,
Folder `/docs`. If you use Pages instead of the custom domain, repoint the absolute URLs at the
Pages URL: the `og:url` / `og:image` / `twitter:image` meta tags, the `<link rel="canonical">`,
the JSON-LD `url` / `image` / `screenshot`, the `<loc>` in `sitemap.xml`, and the `Sitemap:`
line in `robots.txt`.

## Before you ship

No text placeholders remain — the donate buttons (header, support section, footer) link to
Ko-fi (`ko-fi.com/kaarl77`), and the `og:url` / `og:image` tags already point at
`mockmycam.kaarlmoroti.com`. The only thing the **Download** button needs is a published
**GitHub Release** with the built `MockMyCam.app` (zipped) or a `.dmg` attached; it links to the
repo's *latest release*, so it just works once that exists.

## Add media

The "See it in action" section is a 2-up. These live in `docs/assets/` and show automatically
(a labeled placeholder appears if a file is missing):

| File | What it shows | Status |
|---|---|---|
| `assets/screenshot-app.png` | the app + Simulator side by side (menu bar feeding the camera) | ✅ added |
| `assets/demo-video.mp4` | a short clip looped as the camera feed (muted, autoplay, loop) | ✅ added |
| `assets/demo-video-poster.jpg` | poster frame for the video (shown before it plays) | ✅ added |
| `assets/og-image.png` | 1200×630 social-share card (link previews) | ✅ added |
| `assets/favicon.svg` | browser-tab icon — the camera mark on the honey→coral gradient | ✅ added |

The video is a web-optimized H.264 MP4 (transcoded with AVFoundation from a CleanShot screen
recording of the app + Simulator — 656×720, `shouldOptimizeForNetworkUse`, ~2.2 MB). The
`og-image.png` social card is generated with a small CoreGraphics script. To replace either,
drop in a new file of the same name. Media are shown at natural aspect, centered and
height-capped so the two islands stay balanced.
