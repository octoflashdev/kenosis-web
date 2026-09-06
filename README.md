# Kenosis AI — website

Static landing page for [Kenosis AI](https://github.com/) (../kenosis-ai). No build step — plain HTML/CSS/JS, deployed to GitHub Pages.

## Local preview

```sh
python3 -m http.server 8000
# open http://localhost:8000
```

## Adding a screenshot

1. Copy the file into `assets/screenshots/`.
2. Add a `<figure class="shot">` block to `#shot-grid` in `index.html` (copy the existing one).

## Adding a video

1. Copy the file into `assets/videos/` (mp4/webm).
2. Add one entry to the `VIDEOS` array in `js/main.js`:

```js
{ src: 'assets/videos/demo.mp4', title: 'Demo', desc: 'What it shows', poster: 'assets/videos/demo-poster.jpg' /* optional */ },
```

## Deploy (GitHub Pages)

- **Via workflow:** the included `.github/workflows/deploy.yml` publishes the site on every push to `main`. Enable Pages under Settings → Pages → Source: GitHub Actions.
- **Via branch:** Settings → Pages → deploy from `main` / root.

## Structure

- `index.html` — all sections (hero, how-it-works, videos, screenshots, privacy, footer)
- `css/style.css` — dark theme design tokens
- `js/main.js` — `VIDEOS` config, scroll-reveal, screenshot lightbox