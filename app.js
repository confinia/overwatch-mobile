// Overwatch mobile — one question, answered fast: "is my station okay?"
// Reads only open-data GET endpoints; there is nothing to sign into.
const API = "https://overwatch.confinia.io/api/v1";
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

function home(){
  history.replaceState(null, "", "#");
  view.innerHTML =
    `<input type="search" id="q" placeholder="Your callsign or station name…" autocomplete="off">` +
    `<div id="results"></div>`;
  const q = document.getElementById("q");
  q.addEventListener("input", debounce(search, 250));
  q.focus();
  const last = localStorage.getItem(LAST);
  if (last) station(last);        // returning user: straight to their station
  else search();                  // first visit: show the busiest stations
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

  // clamped: rates above 1.0 are real (several frames per pass) and must not
  // overflow the row
  const bars = d.days.slice(-21).map(x =>
    x.hit_rate == null ? `<div class="na" style="height:2px"></div>`
    : `<div style="height:${Math.max(4, Math.round(Math.min(x.hit_rate, 1) * 56))}px" title="${x.day}: ${(x.hit_rate*100).toFixed(0)}%"></div>`).join("");

  const row = p => {
    const when = new Date(p.aos).toLocaleString(undefined,
      { weekday:"short", hour:"2-digit", minute:"2-digit" });
    // past passes carry frames: the per-pass "was it me, or was it quiet?"
    const heard = p.frames == null ? ""
      : p.frames > 0 ? ` <span class="ok">${p.frames} frames</span>`
      : ` <span class="bad">nothing heard</span>`;
    return `<tr><td>${esc(p.satellite)}${heard}</td>` +
           `<td>${when} · ${Math.round(p.max_el_deg)}°</td></tr>`;
  };
  const passes = d.next_passes.map(row).join("");
  const past = (d.past_passes || []).map(row).join("");

  view.innerHTML =
    `<a class="back" href="#" onclick="home();return false">‹ stations</a>` +
    `<div class="card"><b>${esc(d.observer)}</b>` +
    `<div class="big ${cls}">${rate == null ? "—" : (rate*100).toFixed(0) + "%"}</div>` +
    `<div class="meta">${verdict}` +
    (base != null ? ` · your baseline ${(base*100).toFixed(0)}%` : "") + `</div>` +
    `<div class="bars">${bars}</div>` +
    `<div class="meta">hit rate, last ${Math.min(21, d.days.length)} days — frames heard / passes available</div></div>` +
    (passes ? `<div class="card"><b>Next passes</b><table>${passes}</table></div>`
            : `<div class="card meta">No computed passes for this station yet — they cover the most active stations.</div>`) +
    (past ? `<div class="card"><b>Recent passes</b><table>${past}</table></div>` : "");
}

function fail(e){
  view.innerHTML = `<a class="back" href="#" onclick="home();return false">‹ stations</a>` +
    `<div class="card"><b>Couldn't load that</b><div class="meta">${esc(e.message)}</div></div>`;
}

function debounce(fn, ms){ let t; return () => { clearTimeout(t); t = setTimeout(fn, ms); }; }

// Deep link: #<observer> opens that station directly (shareable).
const h = decodeURIComponent(location.hash.slice(1));
if (h){ view.innerHTML = ""; station(h); } else home();
