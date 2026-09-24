#!/usr/bin/env python3
"""Render Play Store phone screenshots from assets/screenshots/ into framed,
captioned 1080x1920 PNGs (phone-NN.png).

Edit the SHOTS table below to change captions, order, or which screenshot is
used, then run:  python3 render.py
Requirements: google-chrome on PATH, Pillow.
"""
import os
import subprocess
import urllib.parse

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1080, 1920

# (screenshot file under ../assets/screenshots/, line 1, gradient line 2, sub-line)
# In sub-line: **bold**, <br> for a line break.
# "fs": "small" shrinks the headline for long titles.
SHOTS = [
    # Shot 1: pitch hero — headline + claim chips on the upper half,
    # three small phones stacked below (back to front).
    dict(shots="transcription.png,RAG02.png,chat-mock.png", fs="small",
         t1="The only AI app without", t2="INTERNET permission",
         sub="**No network. No cloud. No telemetry.**",
         chips="✈ Airplane mode|✕ No ads|✕ No subscriptions|✕ No account"),
    dict(shot="transcription.png",
         t1="Transcribe any video", t2="on-device",
         sub="The transcript can later be exported as **srt subtitles** or an AI natural voice audio."),
    dict(shot="RAG02.png",
         t1="Chat with", t2="your own documents",
         sub="Answers grounded in **your** books and files. ePub, pdf, docx, ppt, md, txt supported."),
    dict(shot="ebook03.png",
         t1="Read EPUBs", t2="laid out like a book",
         sub="With read-aloud in **natural voices**, English, German, French, Spanish, Italian support."),
    dict(shot="epub-audiobook-export02.png",
         t1="Turn any EPUB", t2="into an audiobook",
         sub="Exported as a **chaptered .m4a** — rendered right on your phone."),
    dict(shot="imports02.png",
         t1="Add anything to", t2="the conversation",
         sub="Video, audio, images, e-books, **PDF & Office docs.**"),
    dict(shot="privacy.png",
         t1="Privacy controls", t2="you can see",
         sub="One tap improves privacy even more. Encrypted with keys held in **hardware Keystore** (on supported devices)."),
]


def render(spec, index):
    params = {k: v for k, v in spec.items()}
    url = f"file://{HERE}/phone-screens.html?" + urllib.parse.urlencode(params)
    out = os.path.join(HERE, f"phone-{index:02d}.png")
    tmp = f"/tmp/kenosis-phone-{index:02d}.png"
    subprocess.run(
        ["google-chrome", "--headless=new", "--disable-gpu", "--hide-scrollbars",
         "--force-device-scale-factor=2", f"--window-size={W},{H}",
         f"--screenshot={tmp}", url],
        check=True, capture_output=True)
    Image.open(tmp).convert("RGB").resize((W, H), Image.LANCZOS).save(out, optimize=True)
    src = spec.get('shot') or spec.get('shots')
    print(f"{os.path.basename(out)}  <-  {src}  ({os.path.getsize(out) // 1024} KB)")


if __name__ == "__main__":
    for i, spec in enumerate(SHOTS, 1):
        render(spec, i)
