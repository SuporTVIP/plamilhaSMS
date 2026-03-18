importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

// 🚀 1. LISTENER NO TOPO: Nós roubamos o clique antes do Firebase!
self.addEventListener('notificationclick', (event) => {
  event.stopImmediatePropagation(); // 🛑 Impede o Firebase de tentar processar esse clique
  event.notification.close();

  const trecho = event.notification.data?.trecho ?? '';
  const origin = self.location.origin;
  const url = trecho ? `${origin}/?highlight=${encodeURIComponent(trecho)}` : `${origin}/`;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      const aba = list.find(c => c.url.startsWith(origin));
      if (aba) {
        aba.focus();
        if (trecho) aba.postMessage({ type: 'PLAMILHAS_HIGHLIGHT', trecho });
        return;
      }
      return clients.openWindow(url);
    })
  );
});

// 2. AGORA SIM inicializamos o Firebase
firebase.initializeApp({
  apiKey: "AIzaSyAZjnPjOVnbnyzm0pwcUti4aZrWA6F4Fmk",
  authDomain: 'plamilhasvipaddondevsadm.firebaseapp.com',
  projectId: 'plamilhasvipaddondevsadm',
  storageBucket: 'plamilhasvipaddondevsadm.firebasestorage.app',
  messagingSenderId: '1070254866174',
  appId: '1:1070254866174:web:0b8a46e3ff211f685cafaf',
});

const messaging = firebase.messaging();

// ... (O resto do seu código de Install, Activate, lerFiltros e onBackgroundMessage continua igual aqui para baixo) ...

// Previne instância fantasma: força substituição imediata da versão anterior
self.addEventListener('install', (e) => e.waitUntil(self.skipWaiting()));
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// Lê filtros do IndexedDB gravado pelo Flutter Web (web_filters_sync_web.dart)
function lerFiltros() {
  return new Promise((resolve) => {
    try {
      const req = indexedDB.open('PlamilhasDB', 1);
      req.onupgradeneeded = (e) => {
        if (!e.target.result.objectStoreNames.contains('config'))
          e.target.result.createObjectStore('config', { keyPath: 'key' });
      };
      req.onsuccess = (e) => {
        try {
          const get = e.target.result.transaction('config', 'readonly')
            .objectStore('config').get('USER_FILTERS');
          get.onsuccess = () => resolve(get.result?.value ?? null);
          get.onerror = () => resolve(null);
        } catch (_) { resolve(null); }
      };
      req.onerror = () => resolve(null);
    } catch (_) { resolve(null); }
  });
}

// Espelho de passaNoFiltroBasico() do filter_service.dart
function normalizar(t) {
  return (t || '').toLowerCase()
    .replace(/[áàâãä]/g, 'a').replace(/[éèêë]/g, 'e')
    .replace(/[íìîï]/g, 'i').replace(/[óòôõö]/g, 'o')
    .replace(/[úùûü]/g, 'u').replace(/[ç]/g, 'c')
    .trim().toUpperCase();
}
function bateComFiltro(local, lista) {
  if (!lista || !lista.length) return true;
  const n = normalizar(local);
  for (const f of lista) {
    const p = f.split(' - ');
    if (n.includes(normalizar(p[0])) ||
      (p[1] && n.includes(normalizar(p[1])))) return true;
  }
  return false;
}
// Espelho de passaNoFiltroBasico() do filter_service.dart
function passaNoFiltro(filtros, programa, trecho, detalhes) {
  if (!filtros) return true;
  const prog = (programa || '').toUpperCase();

  const isAzul = prog.includes('AZUL');
  const isLatam = prog.includes('LATAM');
  const isSmiles = prog.includes('SMILES');

  if (isLatam && filtros.latam === false) return false;
  if (isSmiles && filtros.smiles === false) return false;
  if (isAzul && filtros.azul === false) return false;

  // 🚀 A NOVA REGRA NO JAVASCRIPT
  if (!isAzul && !isLatam && !isSmiles) {
    // Retorna false apenas se a chave 'outros' existir e for estritamente false
    if (filtros.outros === false) return false;
  }

  const ori = filtros.origens || [], dst = filtros.destinos || [];
  if (!ori.length && !dst.length) return true;
  const p = (trecho || '').toUpperCase().split('-');
  const oV = (p[0] || '').trim(), dV = (p[1] || '').trim();
  const temVolta = normalizar(detalhes || '').includes('VOLTA');
  return (bateComFiltro(oV, ori) && bateComFiltro(dV, dst)) ||
    (temVolta && bateComFiltro(dV, ori) && bateComFiltro(oV, dst));
}

// onBackgroundMessage é o único handler confiável com firebase-messaging-compat.js
// O SDK intercepta o evento 'push' nativo, então o listener nativo nunca dispara.
messaging.onBackgroundMessage((payload) => {
  const data = payload.data ?? {};
  const programa = data.programa ?? 'Oportunidade VIP';
  const trecho = data.trecho ?? '';
  const detalhes = data.detalhes ?? '';
  const id = data.id ?? `alerta-${Date.now()}`;

  if (data.action !== 'SYNC_ALERTS') return;

  return lerFiltros().then((filtros) => {
    if (!passaNoFiltro(filtros, programa, trecho, detalhes)) {
      console.log(`[SW] Bloqueado: ${programa} | ${trecho}`);
      return;
    }

    // 🚀 A MÁGICA: Avisa todas as abas abertas que chegou um push
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      clients.forEach((client) => {
        client.postMessage({
          type: 'PLAMILHAS_PUSH_RECEIVED',
          payload: data // Enviamos o alerta completo para a aba!
        });
      });
    });

    console.log(`[SW] Notificando: ${programa} | ${trecho}`);
    return self.registration.showNotification(`✈️ ${programa}`, {
      body: trecho,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: id,
      renotify: true,
      data,
      // 🔊 Tenta disparar o som padrão do sistema
      silent: false,
    });
  });
});

