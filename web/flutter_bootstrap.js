{{flutter_js}}
{{flutter_build_config}}

(async () => {
  // Planova requires its API; avoid serving an old UI from the legacy worker.
  try {
    if ('serviceWorker' in navigator) {
      const scope = new URL('./', document.baseURI).href;
      const registrations = await navigator.serviceWorker.getRegistrations();
      let retired = false;
      for (const registration of registrations) {
        const worker = registration.active || registration.waiting || registration.installing;
        if (registration.scope === scope && worker?.scriptURL.includes('/flutter_service_worker.js')) {
          retired = await registration.unregister() || retired;
        }
      }
      if (retired && navigator.serviceWorker.controller?.scriptURL.includes('/flutter_service_worker.js')) {
        location.reload();
        return;
      }
    }
  } catch (_) { /* Storage restrictions must not prevent startup. */ }
  _flutter.loader.load();
})();
