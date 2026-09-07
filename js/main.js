// Kenosis AI site — interactive bits.
// Demos are animated PNGs (APNG) in assets/previews/ — no video files on the site.

(function () {
  document.documentElement.classList.add('js'); // enables scroll-reveal only when JS runs

  // Reveal on scroll
  const io = new IntersectionObserver(
    (entries) => entries.forEach((e) => e.isIntersecting && e.target.classList.add('visible')),
    { threshold: 0.12 }
  );
  document.querySelectorAll('.reveal').forEach((el) => io.observe(el));

  // Lightbox for screenshots and animated demos
  const lb = document.getElementById('lightbox');
  const lbImg = document.getElementById('lightbox-img');
  document.querySelectorAll('.feature-media img, .demo img').forEach((img) => {
    img.addEventListener('click', () => {
      lbImg.src = img.src;
      lbImg.alt = img.alt;
      lb.hidden = false;
    });
  });
  function closeLb() { lb.hidden = true; lbImg.src = ''; }
  lb.addEventListener('click', (e) => { if (e.target !== lbImg) closeLb(); });
  document.querySelector('.lightbox-close').addEventListener('click', closeLb);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeLb(); });

  // Bug report — email hidden behind a human check so scrapers don't harvest it
  const bugLink = document.getElementById('bug-report-link');
  const bugReveal = document.getElementById('bug-reveal');
  const bugAnswer = document.getElementById('bug-answer');
  const bugEmail = document.getElementById('bug-email');
  const bugError = document.getElementById('bug-error');
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
    }
  });
})();