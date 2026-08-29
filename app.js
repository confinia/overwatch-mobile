// Overwatch mobile — one question, answered fast: "is my station okay?"
// Reads only open-data GET endpoints; there is nothing to sign into.
const API = "https://overwatch.confinia.io/api/v1";
// Surface identity (dev key tool): which build am I actually running? Bumped
// with the service-worker shell on every deploy. Shown in the footer, so
// "PWA or native?" and "old shell or new?" are answered by looking, not
// guessing — the confusion cost real debugging time.
const BUILD = "PWA · shell v11";
const view = document.getElementById("view");
const esc = s => { const d = document.createElement("div"); d.textContent = s ?? ""; return d.innerHTML; };

// The station you care about is almost always the same one: remember it and
// open straight onto it. This is the whole reason the app exists.
const LAST = "ovw_station";

async function j(path){
  const r = await fetch(`${API}${path}`);
  if (!r.ok) throw new Error((await r.json().catch(() => ({}))).detail || `HTTP ${r.status}`);
  return r.json();
}

function home(explicit){
  history.replaceState(null, "", "#");
  view.innerHTML =
    `<input type="search" id="q" placeholder="Your callsign or station name…" autocomplete="off">` +
    `<div id="results"></div>`;
  const q = document.getElementById("q");
  q.addEventListener("input", debounce(search, 250));
  q.focus();
  const last = localStorage.getItem(LAST);
  // The open-my-station shortcut applies ONLY at launch. It used to run here
  // unconditionally, so tapping "‹ stations" rendered the list and instantly
  // bounced back to the remembered station — once one was saved, the list
  // was unreachable forever.
  if (last && !explicit) station(last);
  else search();
}

let seq = 0;
async function search(){
  const mine = ++seq;
  const qv = (document.getElementById("q")?.value || "").trim().toLowerCase();
  let stations = [];
  try { stations = await j("/stations"); } catch (e) { return fail(e); }
  if (mine !== seq) return;
  const hits = stations
    .filter(s => !qv || s.observer.toLowerCase().includes(qv))
    .slice(0, 12);
  document.getElementById("results").innerHTML = hits.map(s =>
    `<div class="card hit" onclick="station('${esc(s.observer)}')">` +
    `<div><b>${esc(s.observer)}</b>` +
    `<div class="meta">${s.frames} frames · ${s.satellites} satellites · 7 days</div></div>` +
    `<div class="meta">›</div></div>`).join("")
    || `<div class="card meta">Nothing matching — stations appear once they are heard receiving the tracked fleet.</div>`;
}

async function station(observer){
  view.innerHTML = `<div class="card meta">Loading ${esc(observer)}…</div>`;
  let d;
  try { d = await j(`/stations/${encodeURIComponent(observer)}/health`); }
  catch (e) { return fail(e); }
  localStorage.setItem(LAST, d.observer);
  history.replaceState(null, "", `#${encodeURIComponent(d.observer)}`);
  setTimeout(() => refreshWatchButton(d.observer), 0);

  const rate = d.recent_rate, base = d.baseline_rate;
  // The verdict is RELATIVE — a station that never listened to our fleet is
  // not "bad", and the API's note says so. Colour only when there is a
  // baseline to fall from.
  let cls = "ok", verdict = "hearing as usual";
  if (rate == null || !d.days.length){ cls = "warn"; verdict = "no recent data"; }
  else if (base != null && base >= 0.05 && rate <= base * 0.25){
    cls = "bad"; verdict = "far below your own baseline"; }
  else if (base != null && base >= 0.05 && rate <= base * 0.6){
    cls = "warn"; verdict = "below your own baseline"; }

  // A ratio, not a percentage: several frames arrive per pass, so the value
  // sits naturally above 1 — shown as "293%" it read as nonsense ("293% of
  // what?", mhuebner, 2026-08-29). Bars scale against the window's own peak
  // so the shape survives whatever the station's absolute rate is.
  const fpp = r => r >= 10 ? r.toFixed(0) : r.toFixed(1);
  const win = d.days.slice(-21);
  const peak = Math.max(1, ...win.map(x => x.hit_rate ?? 0));
  const bars = win.map(x =>
    x.hit_rate == null ? `<div class="na" style="height:2px"></div>`
    : `<div style="height:${Math.max(4, Math.round(x.hit_rate / peak * 56))}px" title="${x.day}: ${fpp(x.hit_rate)} frames per pass"></div>`).join("");

  const row = p => {
    // past passes drill into the frame-by-frame view (#368)
    const open = p.frames == null ? "" :
      ` onclick="passDetail('${esc(d.observer)}',${p.norad},'${p.aos}','${esc(p.satellite)}')" style="cursor:pointer"`;
    const when = new Date(p.aos).toLocaleString(undefined,
      { weekday:"short", hour:"2-digit", minute:"2-digit" });
    // past passes carry frames: the per-pass "was it me, or was it quiet?"
    const heard = p.frames == null ? ""
      : p.frames > 0 ? ` <span class="ok">${p.frames} frames</span>`
      : ` <span class="bad">nothing heard</span>`;
    return `<tr${open}><td><a href="#" onclick="event.stopPropagation();` +
           `satCard(${p.norad},'${esc(d.observer)}');return false">${esc(p.satellite)}</a>${heard}</td>` +
           `<td>${when} · ${Math.round(p.max_el_deg)}°${p.frames == null ? "" : " ›"}</td></tr>`;
  };
  const passes = d.next_passes.map(row).join("");
  const past = (d.past_passes || []).map(row).join("");

  view.innerHTML =
    `<a class="back" href="#" onclick="home(true);return false">‹ stations</a>` +
    `<div class="card"><b>${esc(d.observer)}</b>` +
    `<button class="watch" id="watch-btn" onclick="toggleWatch('${esc(d.observer)}')">…</button>` +
    `<div class="big ${cls}">${rate == null ? "—" : fpp(rate)}</div>` +
    `<div class="meta">frames per pass · ${verdict}` +
    (base != null ? ` · your baseline ${fpp(base)}` : "") + `</div>` +
    `<div class="bars">${bars}</div>` +
    `<div class="meta">frames heard per pass available, daily — last ${Math.min(21, d.days.length)} days</div></div>` +
    (passes ? `<div class="card"><b>Next passes</b><table>${passes}</table></div>`
            : `<div class="card meta">No computed passes for this station yet — they cover the most active stations.</div>`) +
    (past ? `<div class="card"><b>Recent passes</b><table>${past}</table></div>` : "");
}

function fail(e){
  view.innerHTML = `<a class="back" href="#" onclick="home(true);return false">‹ stations</a>` +
    `<div class="card"><b>Couldn't load that</b><div class="meta">${esc(e.message)}</div></div>`;
}

function debounce(fn, ms){ let t; return () => { clearTimeout(t); t = setTimeout(fn, ms); }; }

// Deep link: #<observer> opens that station directly (shareable).
const h = decodeURIComponent(location.hash.slice(1));
if (h){ view.innerHTML = ""; station(h); } else home();


/** Frame-by-frame view of one pass (#368). Ticks only around the middle of
 *  the bar suggest a horizon problem; across the whole bar, a healthy chain. */
async function passDetail(observer, norad, aos, name){
  view.innerHTML = `<div class="card meta">Loading pass…</div>`;
  let d;
  try {
    const r = await fetch(`${API}/stations/${encodeURIComponent(observer)}/pass` +
                          `?norad=${norad}&aos=${encodeURIComponent(aos)}`);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    d = await r.json();
  } catch (e) { return fail(e); }
  const t0 = new Date(d.aos).getTime();
  const ticks = d.frames.map(f => {
    const x = Math.min(Math.max((new Date(f.ts).getTime() - t0) / 1000 / d.duration_s, 0), 1);
    return `<div style="position:absolute;left:${(x * 100).toFixed(1)}%;top:0;width:2px;height:16px;` +
           `background:${f.fields > 0 ? "var(--ok)" : "var(--accent)"}"></div>`;
  }).join("");
  const rows = d.frames.map(f =>
    `<tr${f.fields > 0 ? ` onclick="frameView(${norad},'${esc(name)}','${f.ts}','${esc(observer)}','${aos}')" style="cursor:pointer"` : ""}>` +
    `<td>${new Date(f.ts).toLocaleTimeString()}</td>` +
    `<td>${f.fields > 0 ? `<span class="ok">${f.fields} fields decoded ›</span>`
                        : `<span class="meta">received, not decoded</span>`}</td></tr>`).join("");
  view.innerHTML =
    `<a class="back" href="#" onclick="station('${esc(observer)}');return false">‹ ${esc(observer)}</a>` +
    `<div class="card"><b>${esc(name)}</b>` +
    `<div class="meta">${new Date(d.aos).toLocaleString()} · max ${Math.round(d.max_el_deg)}° · ${Math.round(d.duration_s / 60)} min</div>` +
    `<div style="position:relative;height:16px;margin:.8rem 0 .3rem">` +
    `<div style="position:absolute;top:5px;left:0;right:0;height:6px;background:var(--line);border-radius:3px"></div>${ticks}</div>` +
    `<div class="meta">${d.frames.length ? d.frames.length + " frames — position along the bar is position in the pass" : "No frames decoded during this pass."}</div></div>` +
    (rows ? `<div class="card"><b>Frames</b><table>${rows}</table></div>` : "");
}


// --- "Alert me when this station goes quiet" (#373) -------------------------
// Real Web Push, end to end: subscribing sends an actual notification through
// the push service within seconds, on the device that will get the alert.
// The button hides itself when the server has no VAPID keys or the browser
// has no push (iOS needs the app installed to the home screen first).
async function pushState(observer){
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) return null;
  try {
    const k = await fetch(`${API}/push/key`);
    if (!k.ok) return null;
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    return { key: (await k.json()).key, reg, sub };
  } catch (e) { return null; }
}

function subBody(sub){
  const j = sub.toJSON();
  return JSON.stringify({ endpoint: sub.endpoint,
                          p256dh: j.keys.p256dh, auth: j.keys.auth });
}

async function refreshWatchButton(observer){
  const btn = document.getElementById("watch-btn");
  if (!btn) return;
  const st = await pushState(observer);
  if (!st){ btn.style.display = "none"; return; }
  const watching = st.sub &&
    (localStorage.getItem("ovw_watching") || "").split("|").includes(observer);
  btn.textContent = watching ? "🔔 watching — tap to stop"
                             : "🔕 alert me if this station goes quiet";
  btn.dataset.watching = watching ? "1" : "";
}

async function toggleWatch(observer){
  const btn = document.getElementById("watch-btn");
  const st = await pushState(observer);
  if (!st) return;
  const list = (localStorage.getItem("ovw_watching") || "").split("|").filter(Boolean);
  try {
    if (btn.dataset.watching){
      if (st.sub)
        await fetch(`${API}/stations/${encodeURIComponent(observer)}/watch`,
          { method: "DELETE", headers: { "content-type": "application/json" },
            body: subBody(st.sub) });
      localStorage.setItem("ovw_watching",
        list.filter(o => o !== observer).join("|"));
    } else {
      const sub = st.sub || await st.reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlB64(st.key) });
      const r = await fetch(`${API}/stations/${encodeURIComponent(observer)}/watch`,
        { method: "POST", headers: { "content-type": "application/json" },
          body: subBody(sub) });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      if (!list.includes(observer)) list.push(observer);
      localStorage.setItem("ovw_watching", list.join("|"));
    }
  } catch (e) { alert("Couldn't update the alert: " + e.message); }
  refreshWatchButton(observer);
}

function urlB64(s){
  const pad = "=".repeat((4 - s.length % 4) % 4);
  const raw = atob((s + pad).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}


/** In-app satellite card: the light answer to "what is this?". The full
 *  control room (MapLibre + Grafana, tens of MB) stays one explicit link
 *  away instead of being the only door — on the connections our users
 *  actually have, that page is a desk tool, not a pocket one. */
async function satCard(norad, backTo){
  view.innerHTML = `<div class="card meta">Loading…</div>`;
  let sat;
  try {
    const r = await fetch(`${API}/satellites`);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    sat = (await r.json()).find(x => x.norad === norad);
    if (!sat) throw new Error("not in the tracked fleet");
  } catch (e) { return fail(e); }
  const heard = sat.last_frame
    ? new Date(sat.last_frame).toLocaleString() : "never (position only)";
  view.innerHTML =
    `<a class="back" href="#" onclick="station('${esc(backTo)}');return false">‹ ${esc(backTo)}</a>` +
    `<div class="card"><b>${esc(sat.name)}</b> <span class="meta">NORAD ${sat.norad}</span>` +
    (sat.note ? `<div class="meta" style="margin:.4rem 0">${esc(sat.note)}</div>` : "") +
    `<table>` +
    `<tr><td>Altitude</td><td>${Math.round(sat.alt_km)} km</td></tr>` +
    `<tr><td>Position</td><td>${sat.lat.toFixed(1)}°, ${sat.lon.toFixed(1)}°</td></tr>` +
    `<tr><td>Sunlight</td><td>${sat.sunlit ? "☀ sunlit" : "🌑 in eclipse"}</td></tr>` +
    `<tr><td>Last heard</td><td>${heard}</td></tr>` +
    `<tr><td>Telemetry</td><td>${sat.has_telemetry ? "decoded here" : "position only"}</td></tr>` +
    `</table>` +
    `<div class="meta" style="margin-top:.7rem">` +
    `<a href="https://overwatch.confinia.io/#${norad}" target="_blank" rel="noopener">` +
    `open in the full control room ↗</a> <span class="meta">(heavy — globe and dashboards)</span></div>` +
    `</div>`;
}


/** The deepest level: every decoded field of one frame. The question at this
 *  depth is "did it decode SANELY" — a battery at 0.02 V tells a different
 *  story than a missing frame. */
async function frameView(norad, satName, ts, observer, aos){
  view.innerHTML = `<div class="card meta">Loading frame…</div>`;
  let d;
  try {
    const r = await fetch(`${API}/satellites/${norad}/frame?ts=${encodeURIComponent(ts)}`);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    d = await r.json();
  } catch (e) { return fail(e); }
  // Same rule as the Grafana boards (#248): a kaitai path like
  // ax25_frame_payload_..._primary_header_sequence_count is identified by its
  // TAIL, so show the last segments and keep the full name as a tooltip.
  const short = n => {
    if (n.length <= 40) return esc(n);
    const tail = n.split("_").slice(-4).join("_");
    return `<span title="${esc(n)}">…${esc(tail)}</span>`;
  };
  const rows = d.fields.map(f =>
    `<tr><td>${short(f.field)}</td><td>${
      typeof f.value === "number" ? +f.value.toFixed(4) : esc(String(f.value))
    }</td></tr>`).join("");
  view.innerHTML =
    `<a class="back" href="#" onclick="passDetail('${esc(observer)}',${norad},'${aos}','${esc(satName)}');return false">‹ pass</a>` +
    `<div class="card"><b>${esc(satName)}</b> <span class="meta">frame · ${new Date(d.ts).toLocaleTimeString()}</span>` +
    `<table>${rows}</table></div>`;
}
