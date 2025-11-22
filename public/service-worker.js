/**
 * Minimal Service Worker for Turbo Spike Offline Support
 *
 * Strategy: Network-first with cache fallback for ALL requests
 * - Online: Every request goes to network, successful responses are cached, network response returned
 * - Offline: Serve from cache (even if stale) to prevent Turbo navigation errors
 *
 * This keeps the app fully functional when network is unavailable.
 */

const CACHE_NAME = 'showcase-offline-v4';

self.addEventListener('install', (event) => {
  // Skip waiting to activate immediately
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Clean up old caches
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames
          .filter(name => name !== CACHE_NAME)
          .map(name => caches.delete(name))
      );
    })
  );

  // Take control of all clients immediately
  return self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    fetch(event.request)
      .then(response => {
        // Only cache successful GET requests
        if (event.request.method === 'GET' && response.status === 200) {
          const responseToCache = response.clone();

          caches.open(CACHE_NAME).then(cache => {
            cache.put(event.request, responseToCache);
          });
        }

        return response;
      })
      .catch(() => {
        // Network failed - try cache
        return caches.match(event.request).then(cachedResponse => {
          if (cachedResponse) {
            return cachedResponse;
          }

          // No cache available - return a basic error response
          return new Response('Offline - no cached version available', {
            status: 503,
            statusText: 'Service Unavailable'
          });
        });
      })
  );
});
