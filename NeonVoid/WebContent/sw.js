const CACHE_NAME = 'neon-void-v49';
const ASSETS = [
  '/',
  '/index.html',
  '/void-arcade-index.html',
  '/games/2048.html',
  '/games/asteroids.html',
  '/games/breakout.html',
  '/games/crossy-road.html',
  '/games/doodle-jump.html',
  '/games/flappy.html',
  '/games/fps.html',
  '/games/fruit-ninja.html',
  '/games/geometry-dash.html',
  '/games/idle-clicker.html',
  '/games/minesweeper.html',
  '/games/obby.html',
  '/games/pacman.html',
  '/games/platformer.html',
  '/games/pong.html',
  '/games/rhythm.html',
  '/games/snake.html',
  '/games/space-invaders.html',
  '/games/tank-trouble.html',
  '/games/tetris.html',
  '/games/tower-defense.html',
  '/games/tower-defense-2.html',
  '/games/wordle.html',
  '/og.html'
];

// Install: cache all game files
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
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
