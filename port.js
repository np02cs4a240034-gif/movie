(function(){
  var params = new URLSearchParams(window.location.search);
  var override = params.get('api') || window.localStorage.getItem('API_BASE');
  var base = override || window.location.origin;
  window.API_BASE = String(base).replace(/\/$/, '');
  if (override) { window.localStorage.setItem('API_BASE', window.API_BASE); }
})();