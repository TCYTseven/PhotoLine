// Shared header/footer so every page stays consistent.
(function () {
  var root = document.body.getAttribute('data-root') || './';
  var header = document.createElement('header');
  header.className = 'site';
  header.innerHTML =
    '<div class="inner" style="display:flex;align-items:center;justify-content:space-between">' +
    '<a class="brand" href="' + root + '"><span class="mark">🃏</span>PhotoCards</a>' +
    '<nav>' +
    '<a href="' + root + '">Home</a>' +
    '<a href="' + root + 'support/">Support</a>' +
    '<a href="' + root + 'privacy/">Privacy</a>' +
    '<a href="' + root + 'terms/">Terms</a>' +
    '</nav></div>';
  document.body.insertBefore(header, document.body.firstChild);

  var footer = document.createElement('footer');
  footer.innerHTML =
    '<div class="inner">' +
    '<a href="' + root + 'privacy/">Privacy Policy</a>' +
    '<a href="' + root + 'terms/">Terms of Service</a>' +
    '<a href="' + root + 'support/">Support</a>' +
    '<a href="' + root + 'licenses/">Credits &amp; licenses</a>' +
    '<div style="margin-top:8px">&copy; ' + new Date().getFullYear() + ' PhotoCards. All rights reserved.</div>' +
    '</div>';
  document.body.appendChild(footer);
})();
