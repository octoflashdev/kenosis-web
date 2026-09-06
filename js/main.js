// Kenosis AI site — videos are configured here.
// Add your file to assets/videos/ and one entry to this list.
const VIDEOS = [
  // { src: 'assets/videos/demo-share.mp4', title: 'Sharing a video', desc: 'From the share sheet to analysis.' },
];

(function () {
  document.documentElement.classList.add('js'); // enables scroll-reveal only when JS runs

  const grid = document.getElementById('video-grid');
  const placeholder =
    '<div class="placeholder"><span class="plus">＋</span>' +
    '<strong>No videos yet</strong><span>Add one to <code>assets/videos/</code> and list it in <code>js/main.js</code>.</span></div>';

  if (!VIDEOS.length) {
    grid.innerHTML = placeholder;
  } else {
    grid.innerHTML = VIDEOS.map(
      (v) =>
        '<figure class="video-card card">' +
        `<video controls preload="metadata" src="${v.src}"${v.poster ? ` poster="${v.poster}"` : ''}></video>` +
        `<h3>${v.title}</h3><p>${v.desc || ''}</p></figure>`
    ).join('');
  }

  // Reveal on scroll
  const io = new IntersectionObserver(
    (entries) => entries.forEach((e) => e.isIntersecting && e.target.classList.add('visible')),
    { threshold: 0.12 }
  );
  document.querySelectorAll('.reveal').forEach((el) => io.observe(el));

  // Lightbox for screenshots
  const lb = document.getElementById('lightbox');
  const lbImg = document.getElementById('lightbox-img');
  document.querySelectorAll('#shot-grid .shot img').forEach((img) => {
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
})();