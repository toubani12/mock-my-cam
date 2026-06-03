# MockMyCam landing page

A single static page (`index.html`) — no build step, no dependencies. Theme: *"islands in a
dawn sky"* — a light, glass-panel ("floating islands") look with hand-authored CSS. The only
runtime fetch is the web fonts from Google Fonts (**Fraunces** display serif, **Hanken
Grotesk** body, **Spline Sans Mono** for code). Just open the file or host the folder.

## Preview locally

```bash
# from the repo root
python3 -m http.server -d docs 8000
# → http://localhost:8000
```

(Or simply open `docs/index.html` in a browser.)

## Publish

The site is plain static files — `index.html` + the `assets/` folder. Host it anywhere.

**On your own server (aaPanel etc.)** — production home: **https://mockmycam.kaarlmoroti.com/**
Upload `index.html` and `assets/` into the site's document root (e.g. `/www/wwwroot/<site>/`),
keeping them side by side (the page uses relative `assets/…` paths). A ready-made
`mockmycam-site.zip` (repo root, git-ignored) contains exactly those — upload it and unzip in place.

**GitHub Pages (free alternative)** — Settings → Pages → *Deploy from a branch*, Branch `main`,
Folder `/docs`. If you use Pages instead of the custom domain, point the `og:url` / `og:image`
meta tags in `index.html` back at the Pages URL.

## Before you ship

No text placeholders remain — the Buy Me a Coffee buttons were removed, and the `og:url` /
`og:image` tags already point at `mockmycam.kaarlmoroti.com`. The only thing the **Download**
button needs is a published **GitHub Release** with the built `MockMyCam.app` (zipped) or a
`.dmg` attached; it links to the repo's *latest release*, so it just works once that exists.

## Add media

The "See it in action" section is a 2-up. These live in `docs/assets/` and show automatically
(a labeled placeholder appears if a file is missing):

| File | What it shows | Status |
|---|---|---|
| `assets/screenshot-app.png` | the app + Simulator side by side (menu bar feeding the camera) | ✅ added |
| `assets/demo-video.mp4` | a short clip looped as the camera feed (muted, autoplay, loop) | ✅ added |
| `assets/demo-video-poster.jpg` | poster frame for the video (shown before it plays) | ✅ added |
| `assets/og-image.png` | 1200×630 social-share card (link previews) | ✅ added |

The video is a web-optimized H.264 MP4 (transcoded with AVFoundation from a CleanShot screen
recording of the app + Simulator — 656×720, `shouldOptimizeForNetworkUse`, ~2.2 MB). The
`og-image.png` social card is generated with a small CoreGraphics script. To replace either,
drop in a new file of the same name. Media are shown at natural aspect, centered and
height-capped so the two islands stay balanced.
