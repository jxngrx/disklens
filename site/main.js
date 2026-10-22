(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (id) => document.getElementById(id);

  /* ---------- hero: a treemap you inspect with a lens ---------- */
  const field = $("field"), base = $("baseLayer"), lit = $("litLayer"), lens = $("lens"), hint = $("hint");
  const DATA = [ // [name, GB, colour] – colours follow the app's category legend
    ["Xcode DerivedData", 38, "#2f6fdd"], ["node_modules", 24, "#2f9e62"], ["Docker.raw", 21, "#6a5fd6"],
    ["iOS Simulators", 16, "#2f6fdd"], [".gradle", 11, "#1f9a96"], ["Movies", 9, "#d2457f"],
    ["Pods", 7, "#2f6fdd"], ["target", 6, "#e4793b"], ["Library/Caches", 5, "#6b7280"],
    [".npm", 4, "#2f9e62"], ["Photos", 3.5, "#d2457f"], ["Android SDK", 3, "#1f9a96"], [".cargo", 2, "#e4793b"],
  ];
  let r = 130, px = 0, py = 0, tx = 0, ty = 0, moved = false, W = 0, H = 0;

  // slice-and-dice on the larger side: simple, stable, good enough for a backdrop
  function layout(items, x, y, w, h, out) {
    if (items.length === 1) return out.push([items[0], x, y, w, h]);
    const total = items.reduce((s, i) => s + i[1], 0);
    let acc = 0, k = 0;
    while (k < items.length - 1 && acc + items[k][1] <= total / 2) acc += items[k++][1];
    k = Math.max(1, k); acc = items.slice(0, k).reduce((s, i) => s + i[1], 0);
    const f = acc / total;
    if (w >= h) { layout(items.slice(0, k), x, y, w * f, h, out); layout(items.slice(k), x + w * f, y, w * (1 - f), h, out); }
    else { layout(items.slice(0, k), x, y, w, h * f, out); layout(items.slice(k), x, y + h * f, w, h * (1 - f), out); }
  }

  function build() {
    W = field.clientWidth; H = field.clientHeight;
    const cells = []; layout(DATA, 6, 6, W - 12, H - 12, cells);
    const html = (lit_) => cells.map(([[n, gb, c], x, y, w, h]) =>
      `<div class="tile" style="left:${x + 3}px;top:${y + 3}px;width:${w - 6}px;height:${h - 6}px;--c:${c}">${
        lit_ ? `<b>${n}</b><span>${gb} GB</span>` : ""}</div>`).join("");
    base.innerHTML = html(false); lit.innerHTML = html(true);
    r = Math.max(84, Math.min(150, W * 0.14));
    field.style.setProperty("--r", r + "px");
  }

  function paint() {
    lit.style.setProperty("--x", px + "px"); lit.style.setProperty("--y", py + "px");
    lens.style.setProperty("--px", px + "px"); lens.style.setProperty("--py", py + "px");
    lens.style.setProperty("--r", r + "px"); lit.style.setProperty("--r", r + "px");
  }

  function tickHero(t) {
    if (!moved) { // idle drift until the visitor takes over
      tx = W * (0.62 + 0.22 * Math.sin(t / 2600)); ty = H * (0.36 + 0.2 * Math.sin(t / 1900 + 1));
    }
    px += (tx - px) * 0.12; py += (ty - py) * 0.12; paint();
    requestAnimationFrame(tickHero);
  }

  build(); px = tx = W * 0.65; py = ty = H * 0.38; paint();
  addEventListener("resize", () => { build(); paint(); });
  const hero = document.querySelector(".hero");
  hero.addEventListener("pointermove", (e) => {
    const b = field.getBoundingClientRect(); tx = e.clientX - b.left; ty = e.clientY - b.top;
    if (!moved) { moved = true; hint.classList.add("gone"); }
  });
  hero.addEventListener("pointerleave", () => { moved = false; });
  if (!reduce) requestAnimationFrame(tickHero);

  /* ---------- scroll tour: window settles flat, screenshots swap ---------- */
  const tour = document.querySelector(".tour"), win = $("win"), rail = $("railFill");
  const shots = [...document.querySelectorAll(".shot")], steps = [...document.querySelectorAll(".steps li")];
  let cur = -1, ticking = false;
  const clamp = (v) => Math.min(1, Math.max(0, v));
  const ease = (t) => 1 - Math.pow(1 - t, 3);

  function update() {
    ticking = false;
    const b = tour.getBoundingClientRect(), span = b.height - innerHeight;
    const p = clamp(-b.top / span);
    const settle = ease(clamp(p / 0.22));
    win.style.setProperty("--rx", (14 * (1 - settle)).toFixed(2) + "deg");
    win.style.setProperty("--ry", (-10 * (1 - settle)).toFixed(2) + "deg");
    win.style.setProperty("--sc", (0.9 + 0.1 * settle).toFixed(3));
    rail.parentElement.style.setProperty("--p", p.toFixed(3)); rail.style.setProperty("--p", p.toFixed(3));
    const i = Math.min(2, Math.floor(p * 3));
    if (i !== cur) {
      cur = i;
      shots.forEach((s, k) => s.classList.toggle("on", k === i));
      steps.forEach((s, k) => s.classList.toggle("on", k === i));
    }
  }
  if (!reduce) {
    addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    addEventListener("resize", update); update();
  }
})();
