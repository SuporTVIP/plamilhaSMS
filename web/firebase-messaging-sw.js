importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyAZjnPjOVnbnyzm0pwcUti4aZrWA6F4Fmk",
  authDomain: 'plamilhasvipaddondevsadm.firebaseapp.com',
  projectId: 'plamilhasvipaddondevsadm',
  storageBucket: 'plamilhasvipaddondevsadm.firebasestorage.app',
  messagingSenderId: '1070254866174',
  appId: '1:1070254866174:web:0b8a46e3ff211f685cafaf',
});

const messaging = firebase.messaging();

// ─────────────────────────────────────────────────────────────────────────────
// RECEPÇÃO DA NOTIFICAÇÃO (APENAS O NATIVO)
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data = {};
  try {
    const json = event.data.json();
    data = json.data ?? json;
  } catch (_) {
    return;
  }

  if (data.action !== 'SYNC_ALERTS') return;

  const programa = data.programa ?? 'Oportunidade VIP';
  const trecho = data.trecho ?? 'Nova emissão encontrada!';
  const id = data.id ?? `alerta-${Date.now()}`;

  event.waitUntil(
    self.registration.showNotification(`✈️ ${programa}`, {
      body: trecho,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: id,
      renotify: true,
      data: data,
    })
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// CLIQUE NA NOTIFICAÇÃO → Foca a aba ou abre nova
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close(); // Fecha o balãozinho do Windows

  const data = event.notification.data ?? {};
  const trecho = data.trecho ?? '';

  const origin = self.location.origin;
  // Monta a URL. Se tiver trecho, empacota na URL
  const urlComTrecho = trecho ? `${origin}/?highlight=${encodeURIComponent(trecho)}` : `${origin}/`;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // 1. Tenta achar a aba do sistema já aberta
      for (let i = 0; i < windowClients.length; i++) {
        const client = windowClients[i];
        if (client.url.startsWith(origin) && 'focus' in client) {
          client.focus(); // Traz a aba pra frente
          if (trecho) {
            client.postMessage({ type: 'PLAMILHAS_HIGHLIGHT', trecho: trecho });
          }
          return;
        }
      }

      // 2. Se a aba não existe (fechada), abre do zero com o trecho na URL
      if (clients.openWindow) {
        return clients.openWindow(urlComTrecho);
      }
    })
  );
});