// web/firebase-messaging-sw.js
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

// Notificação quando a aba está em background ou fechada
messaging.onBackgroundMessage((payload) => {
  const programa = payload.data?.programa ?? 'Oportunidade VIP';
  const trecho = payload.data?.trecho ?? 'Nova emissão encontrada!';
  const id = payload.data?.id ?? `alerta-${Date.now()}`;

  self.registration.showNotification(`✈️ ${programa}`, {
    body: trecho,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: id,       // impede empilhar notificações do mesmo alerta
    data: payload.data,
    requireInteraction: false,
  });
});

// Clique na notificação do sistema → foca a aba ou abre nova
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (client.url.includes(self.location.origin) && 'focus' in client) {
            return client.focus();
          }
        }
        return clients.openWindow('/');
      })
  );
});