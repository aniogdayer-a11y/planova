// Replace the legacy Flutter cache worker without touching account/local data.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const name of ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']) {
    await caches.delete(name);
  }
  await self.registration.unregister();
  const windows = await self.clients.matchAll({type:'window'});
  await Promise.all(windows.filter(client => client.url.startsWith(self.registration.scope))
    .map(client => client.navigate(client.url)));
})()));
