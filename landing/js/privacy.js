(function () {
  var fab = document.getElementById('fab');
  var panel = document.getElementById('toc-panel');
  var overlay = document.getElementById('toc-overlay');
  var closeBtn = document.getElementById('toc-close');
  var links = document.querySelectorAll('#toc-list a');

  function open() {
    panel.classList.add('open');
    overlay.classList.add('open');
    fab.setAttribute('aria-expanded', 'true');
    panel.setAttribute('aria-hidden', 'false');
  }
  function close() {
    panel.classList.remove('open');
    overlay.classList.remove('open');
    fab.setAttribute('aria-expanded', 'false');
    panel.setAttribute('aria-hidden', 'true');
  }
  function toggle() {
    if (panel.classList.contains('open')) close(); else open();
  }

  fab.addEventListener('click', toggle);
  closeBtn.addEventListener('click', close);
  overlay.addEventListener('click', close);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && panel.classList.contains('open')) close();
  });

  // Ferme 150ms après un clic sur un lien (laisse le scroll démarrer)
  links.forEach(function (a) {
    a.addEventListener('click', function () {
      setTimeout(close, 150);
    });
  });

  // Scrollspy
  var sections = document.querySelectorAll('main.doc section[id]');
  var byId = {};
  links.forEach(function (a) {
    var id = a.getAttribute('data-target');
    byId[id] = a;
  });

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      var id = entry.target.id;
      var link = byId[id];
      if (!link) return;
      if (entry.isIntersecting) {
        links.forEach(function (l) { l.classList.remove('active'); });
        link.classList.add('active');
      }
    });
  }, { rootMargin: '-30% 0px -60% 0px', threshold: 0 });

  sections.forEach(function (s) { io.observe(s); });
})();
