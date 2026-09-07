# Kenosis AI — website

Static landing page for **Kenosis AI** (app source at `../kenosis-ai`, not open source). No build step — plain HTML/CSS/JS, deployed to GitHub Pages.

- Play Store: https://play.google.com/store/apps/details?id=hr.exel.kenosis_ai
- Reddit: https://www.reddit.com/r/Kenosis_AI/
- Bug reports: octoflash.dev@gmail.com (revealed on-site behind a human check to deter scrapers)

## Local preview

```sh
python3 -m http.server 8000
# open http://localhost:8000
```

## Media

The site ships **no video files** — demos are animated PNGs (APNG), so the page stays light.

### Adding a screenshot

1. Copy the file into `assets/screenshots/`.
2. Reference it from a feature card in the `#features` section of `index.html` (screenshots open full-size in a lightbox).

### Adding an animated demo

1. Cut a screen recording (`videocaptures/foo.mp4`, outside the repo).
2. Export an animated PNG, then wire it into the `#demos` grid in `index.html`:

```sh
ffmpeg -t 8 -i foo.mp4 -vf "fps=10,scale=360:-2:flags=lanczos" -plays 0 -f apng assets/previews/foo.png
```

Keep exports under ~3 MB each — they load on the homepage.

## Deploy (GitHub Pages)

- **Via workflow:** the included `.github/workflows/static.yml` publishes the site on every push to `main`. Enable Pages under Settings → Pages → Source: GitHub Actions.
- **Via branch:** Settings → Pages → deploy from `main` / root.

## Structure

- `index.html` — all sections (hero, features, demos, privacy, FAQ, footer)
- `css/style.css` — dark theme design tokens
- `js/main.js` — scroll-reveal, lightbox, bug-report captcha
- `assets/screenshots/` — feature screenshots
- `assets/previews/` — animated PNG demos