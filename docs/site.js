(function () {
  var root = document.documentElement;
  var KEY = "cdesk-theme";
  function get() { try { return localStorage.getItem(KEY) || "system"; } catch (e) { return "system"; } }
  function apply(t) {
    if (t === "light" || t === "dark") root.setAttribute("data-theme", t);
    else root.removeAttribute("data-theme");
  }
  apply(get());
  var labels = { system: "System", light: "Light", dark: "Dark" };
  var order = ["system", "light", "dark"];

  function init() {
    var tb = document.querySelector(".theme-btn");
    function paint() {
      var t = get();
      if (tb) {
        tb.textContent = "Theme: " + labels[t];
        tb.setAttribute("aria-label", "Colour theme: " + labels[t] + ". Click to change.");
      }
    }
    if (tb) {
      tb.addEventListener("click", function () {
        var next = order[(order.indexOf(get()) + 1) % order.length];
        try { localStorage.setItem(KEY, next); } catch (e) {}
        apply(next); paint();
      });
      paint();
    }
    var mb = document.querySelector(".menu-btn");
    var nav = document.getElementById("site-nav");
    if (mb && nav) {
      mb.addEventListener("click", function () {
        var open = nav.classList.toggle("open");
        mb.setAttribute("aria-expanded", open ? "true" : "false");
      });
    }
    var btns = document.querySelectorAll(".copy");
    Array.prototype.forEach.call(btns, function (b) {
      b.addEventListener("click", function () {
        var code = b.parentNode.querySelector("code");
        var text = code ? code.textContent : "";
        function done(ok) {
          b.textContent = ok ? "Copied" : "Press Cmd-C";
          setTimeout(function () { b.textContent = "Copy"; }, 1800);
        }
        function fallback() {
          var ta = document.createElement("textarea");
          ta.value = text; ta.setAttribute("readonly", "");
          ta.style.position = "fixed"; ta.style.opacity = "0";
          document.body.appendChild(ta); ta.select();
          var ok = false;
          try { ok = document.execCommand("copy"); } catch (e) {}
          document.body.removeChild(ta);
          if (!ok && code) {
            var r = document.createRange(); r.selectNodeContents(code);
            var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
          }
          done(ok);
        }
        if (navigator.clipboard && window.isSecureContext) {
          navigator.clipboard.writeText(text).then(function () { done(true); }, fallback);
        } else { fallback(); }
      });
    });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
