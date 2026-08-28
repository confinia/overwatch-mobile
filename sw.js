// Cache the SHELL, never the data. A stale hit-rate that looks fresh is worse
// than a spinner: this app exists to answer "is my station okay RIGHT NOW".
const SHELL = "ovw-shell-v5";
const ASSETS = ["./", "index.html", "app.js", "manifest.webmanifest", "icon.svg"];
self.addEventListener("install", e =>
  e.waitUntil(caches.open(SHELL).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting())));
self.addEventListener("activate", e =>
  e.waitUntil(caches.keys().then(ks =>
    Promise.all(ks.filter(k => k !== SHELL).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  if (url.origin === location.origin)
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request)));
  // cross-origin (the API): always network — data must be live
});


// Web Push (#373): show the alert, and opening it lands on the station.
self.addEventListener("push", e => {
  const d = e.data ? e.data.json() : {};
  e.waitUntil(self.registration.showNotification(d.title || "Overwatch", {
    body: d.body || "", icon: "icon-192.png", badge: "icon-192.png",
    data: { observer: d.observer || "" }, tag: d.observer || "overwatch",
  }));
});
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const obs = e.notification.data && e.notification.data.observer;
  const url = obs ? `./#${encodeURIComponent(obs)}` : "./";
  e.waitUntil(clients.matchAll({ type: "window" }).then(ws => {
    for (const w of ws) if ("focus" in w) return w.focus();
    return clients.openWindow(url);
  }));
});
