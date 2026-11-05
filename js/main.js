// Kenosis AI site — interactive bits.
// Demos are animated PNGs (APNG) in assets/previews/ — no video files on the site.

(function () {
  document.documentElement.classList.add('js'); // enables scroll-reveal only when JS runs

  // Reveal on scroll
  const reveal = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(
      (entries) => entries.forEach((e) => e.isIntersecting && e.target.classList.add('visible')),
      { threshold: 0.12 }
    );
    reveal.forEach((el) => io.observe(el));
  } else {
    reveal.forEach((el) => el.classList.add('visible'));
  }

  // Lightbox for screenshots and animated demos (only on pages that include it)
  const lb = document.getElementById('lightbox');
  const lbImg = document.getElementById('lightbox-img');
  const lbClose = document.querySelector('.lightbox-close');
  if (lb && lbImg && lbClose) {
    document.querySelectorAll('.feature-media img, .demo img').forEach((img) => {
      img.addEventListener('click', () => {
        lbImg.src = img.src;
        lbImg.alt = img.alt;
        lb.hidden = false;
      });
    });
    function closeLb() { lb.hidden = true; lbImg.src = ''; }
    lb.addEventListener('click', (e) => { if (e.target !== lbImg) closeLb(); });
    lbClose.addEventListener('click', closeLb);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeLb(); });
  }

  // Bug report — email hidden behind a human check so scrapers don't harvest it
  const bugLink = document.getElementById('bug-report-link');
  const bugReveal = document.getElementById('bug-reveal');
  const bugAnswer = document.getElementById('bug-answer');
  const bugEmail = document.getElementById('bug-email');
  const bugError = document.getElementById('bug-error');
  if (bugLink && bugReveal && bugAnswer && bugEmail && bugError) {
    bugLink.addEventListener('click', (e) => {
      e.preventDefault();
      bugReveal.hidden = false;
      bugAnswer.focus();
    });
    bugAnswer.addEventListener('input', () => {
      if (Number(bugAnswer.value) === 12) {
        bugEmail.hidden = false;
        bugError.hidden = true;
      } else if (bugAnswer.value !== '') {
        bugError.hidden = false;
        bugEmail.hidden = true;
      } else {
        bugEmail.hidden = true;
        bugError.hidden = true;
      }
    });
  }
})();
