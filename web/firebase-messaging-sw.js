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
// RECEPÇÃO DA NOTIFICAÇÃO
// Usamos o evento 'push' NATIVO como fonte de verdade.
// É mais confiável que onBackgroundMessage porque dispara SEMPRE,
// independente de o GAS mandar o campo 'notification' ou não.
// O onBackgroundMessage do Firebase fica como fallback de compatibilidade.
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data = {};
  try {
    // FCM envolve o payload numa chave 'data' dentro do JSON do push
    const json = event.data.json();
    data = json.data ?? json; // suporta ambos os formatos
  } catch (_) {
    return; // payload malformado — ignora
  }

  const programa = data.programa ?? 'Oportunidade VIP';
  const trecho = data.trecho ?? 'Nova emissão encontrada!';
  const id = data.id ?? `alerta-${Date.now()}`;

  // Só mostra se for um alerta válido do sistema
  if (data.action !== 'SYNC_ALERTS') return;

  event.waitUntil(
    self.registration.showNotification(`✈️ ${programa}`, {
      body: trecho,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: id,       // evita empilhar a mesma emissão
      renotify: true,     // vibra mesmo se substituir uma com mesmo tag
      requireInteraction: false,
      data: data,     // payload completo viaja com a notificação
    })
  );
});

// Fallback Firebase SDK — cobre casos onde o push chega via FCM SDK diretamente
messaging.onBackgroundMessage((payload) => {
  // O evento 'push' acima já tratou — só age se ele não mostrou nada
  // (self.registration.getNotifications verifica se já há uma com esse tag)
  const data = payload.data ?? {};
  const id = data.id ?? `alerta-${Date.now()}`;

  event?.waitUntil?.(
    self.registration.getNotifications({ tag: id }).then((existing) => {
      if (existing.length > 0) return; // push nativo já exibiu, não duplica

      const programa = data.programa ?? 'Oportunidade VIP';
      const trecho = data.trecho ?? 'Nova emissão encontrada!';

      return self.registration.showNotification(`✈️ ${programa}`, {
        body: trecho,
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        tag: id,
        data: data,
      });
    })
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// CLIQUE NA NOTIFICAÇÃO → abre o app E passa o trecho para o blur dourado
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data ?? {};
  const trecho = data.trecho ?? '';

  // URL base do app. Se o trecho existir, passa como query param
  // para o Flutter ler no cold start (quando nenhuma aba está aberta).
  const urlBase = new URL('/', self.location.origin).href;
  const urlComTrecho = trecho
    ? `${urlBase}?highlight=${encodeURIComponent(trecho)}`
    : urlBase;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((windowClients) => {

        // Tenta encontrar uma aba do app já aberta (qualquer rota)
        const abaAberta = windowClients.find(
          (c) => c.url.startsWith(self.location.origin)
        );

        if (abaAberta) {
          // Aba já existe: foca e manda postMessage com o trecho
          // O Flutter escuta via window.onMessage e chama setPendingHighlight
          return abaAberta.focus().then(() => {
            if (trecho) {
              abaAberta.postMessage({
                type: 'PLAMILHAS_HIGHLIGHT',
                trecho: trecho,
              });
            }
          });
        }

        // Nenhuma aba aberta: abre nova passando o trecho na URL
        return clients.openWindow(urlComTrecho);
      })
  );
});