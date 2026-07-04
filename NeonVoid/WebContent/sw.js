const CACHE_NAME = 'neon-void-v74';
// Precache ONLY the Last Pilot game's own assets. The Void Arcade portal and its
// mini-games are a separate product; they are still served and runtime-cached on
// first visit (see fetch handler) but no longer bloat the game's install.
const ASSETS = [
  '/',
  '/index.html',
  '/og.html',
  '/manifest.json',
  '/icon-512.png',
  '/apple-touch-icon.png'
];

// Install: precache core assets resiliently (one 404 must not abort the whole install)
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => Promise.allSettled(ASSETS.map(a => cache.add(a))))
  );
  self.skipWaiting();
});

// Activate: clean old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch: cache-first for local assets, network-first for API calls
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Network-first for cloud saves and external APIs
  if (url.hostname !== self.location.hostname) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
    return;
  }

  // Network-first for local files (always get latest, fall back to cache offline)
  event.respondWith(
    fetch(event.request).then(response => {
      if (response.ok) {
        const clone = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
      }
      return response;
    }).catch(() => caches.match(event.request))
  );
});
