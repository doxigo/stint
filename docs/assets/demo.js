// The landing page's popover demo. Sample data only: nothing is stored and nothing leaves the page.
const stage = document.querySelector("[data-demo]");
if (stage) {
  const pop = stage.querySelector("[data-pop]");
  const badge = stage.querySelector("[data-badge]");
  const glyph = stage.querySelector("[data-badge-glyph]");
  const badgeTime = stage.querySelector("[data-badge-time]");
  const clock = stage.querySelector("[data-clock]");
  const totals = stage.querySelectorAll("[data-total]");
  const timers = stage.querySelector("[data-timers]");
  const logged = [...stage.querySelectorAll("[data-logged]")].reduce((sum, row) => sum + +row.dataset.seconds, 0);

  const hm = (s) => `${Math.floor(s / 3600)}:${String(Math.floor(s / 60) % 60).padStart(2, "0")}`;
  const hms = (s) => `${hm(s)}:${String(s % 60).padStart(2, "0")}`;
  const spoken = (s) => `${Math.floor(s / 3600) ? `${Math.floor(s / 3600)} hours ` : ""}${Math.floor(s / 60) % 60} minutes`;
  const label = { pause: '<svg class="i fill" aria-hidden="true"><use href="#i-pause"/></svg><span>Pause</span>',
                  start: '<svg class="i" aria-hidden="true"><use href="#i-start"/></svg><span>Start</span>' };

  let running = timers.querySelector(".is-running");
  let latest = running; // the status item shows the running timer, or the last one that ran
  let now = 14 * 3600 + 32 * 60 + 12; // the sample day's wall clock
  let lastTick = Date.now();

  const render = () => {
    const rows = [...timers.children];
    for (const row of rows) row.querySelector(".row-time").textContent = hm(+row.dataset.seconds);
    const total = logged + rows.reduce((sum, row) => sum + +row.dataset.seconds, 0);
    for (const t of totals) t.textContent = hm(total);
    badgeTime.textContent = hms(+latest.dataset.seconds);
    clock.textContent = hm(now);
  };

  const describe = () => {
    const state = running ? "running" : "paused";
    badge.setAttribute("aria-label", `Stint, ${state}, ${spoken(+latest.dataset.seconds)}. Show or hide the popover.`);
    badge.classList.toggle("is-paused", !running);
    glyph.setAttribute("href", running ? "#i-pause" : "#i-play");
  };

  const set = (row, on) => {
    row.classList.toggle("is-running", on);
    row.classList.toggle("is-paused", !on);
    row.querySelector(".row-btn").innerHTML = on ? label.pause : label.start;
  };

  // Starting a timer pauses the one that's running, as in the app.
  const start = (row) => {
    if (running) set(running, false);
    set(row, true);
    running = latest = row;
  };

  stage.addEventListener("click", (event) => {
    const button = event.target.closest(".row-btn");
    if (!button) return;
    const row = button.closest(".row");
    if (row.hasAttribute("data-logged")) {
      // Start on a logged entry continues that task as a timer.
      let timer = [...timers.children].find((r) => r.dataset.task === row.dataset.task);
      if (!timer) {
        timer = row.cloneNode(true);
        timer.removeAttribute("data-logged");
        timer.dataset.seconds = "0";
        timers.append(timer);
      }
      start(timer);
    } else if (row === running) {
      set(row, false);
      running = null;
    } else {
      start(row);
    }
    describe();
    render();
  });

  badge.addEventListener("click", () => {
    pop.hidden = !pop.hidden;
    badge.setAttribute("aria-expanded", String(!pop.hidden));
  });
  stage.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !pop.hidden) {
      pop.hidden = true;
      badge.setAttribute("aria-expanded", "false");
      badge.focus();
    }
  });

  setInterval(() => {
    const elapsed = Math.round((Date.now() - lastTick) / 1000);
    if (!elapsed) return;
    lastTick += elapsed * 1000;
    now += elapsed;
    if (running) {
      const minuteBefore = Math.floor(+running.dataset.seconds / 60);
      running.dataset.seconds = String(+running.dataset.seconds + elapsed);
      if (Math.floor(+running.dataset.seconds / 60) !== minuteBefore) describe();
    }
    render();
  }, 1000);
  render();
}
