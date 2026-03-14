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
// PREVENÇÃO DE INSTÂNCIA FANTASMA
// skipWaiting: força este SW a substituir qualquer versão anterior imediatamente,
// evitando que tabs antigas fiquem presas numa versão desatualizada.
// clients.claim: assume controle imediato de todas as abas abertas.
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// ─────────────────────────────────────────────────────────────────────────────
// LEITURA DE FILTROS DO IndexedDB
// O Flutter Web grava os filtros aqui via web_filters_sync_web.dart.
// O SW lê antes de decidir se exibe a notificação.
// Por que IndexedDB? É o único storage acessível tanto pelo Flutter Web
// (thread principal) quanto pelo Service Worker (contexto isolado).
// ─────────────────────────────────────────────────────────────────────────────
function lerFiltros() {
  return new Promise((resolve) => {
    const req = indexedDB.open('PlamilhasDB', 1);

    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains('config')) {
        db.createObjectStore('config', { keyPath: 'key' });
      }
    };

    req.onsuccess = (e) => {
      try {
        const db = e.target.result;
        const tx = db.transaction('config', 'readonly');
        const store = tx.objectStore('config');
        const get = store.get('USER_FILTERS');
        get.onsuccess = () => resolve(get.result?.value ?? null);
        get.onerror = () => resolve(null);
      } catch (_) {
        resolve(null);
      }
    };

    req.onerror = () => resolve(null);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// LÓGICA DE FILTRO — espelho exato de passaNoFiltroBasico() no Dart
// Qualquer mudança na lógica do filter_service.dart deve ser replicada aqui.
// ─────────────────────────────────────────────────────────────────────────────
function normalizar(texto) {
  return texto
    .toLowerCase()
    .replace(/[áàâãä]/g, 'a')
    .replace(/[éèêë]/g, 'e')
    .replace(/[íìîï]/g, 'i')
    .replace(/[óòôõö]/g, 'o')
    .replace(/[úùûü]/g, 'u')
    .replace(/[ç]/g, 'c')
    .trim()
    .toUpperCase();
}

function bateComFiltro(localVoo, listaUsuario) {
  if (!listaUsuario || listaUsuario.length === 0) return true;
  const localNorm = normalizar(localVoo);
  for (const filtro of listaUsuario) {
    const partes = filtro.split(' - ');
    const iata = normalizar(partes[0]);
    const cidade = partes.length > 1 ? normalizar(partes[1]) : '';
    if (localNorm.includes(iata) || (cidade && localNorm.includes(cidade))) return true;
  }
  return false;
}

function passaNoFiltro(filtros, programa, trecho, detalhes) {
  // Sem filtros salvos ainda → notifica tudo (comportamento padrão)
  if (!filtros) return true;

  const prog = (programa || '').toUpperCase();
  const det = normalizar(detalhes || '');

  // 1. Filtro por companhia
  if (prog.includes('LATAM') && filtros.latam === false) return false;
  if (prog.includes('SMILES') && filtros.smiles === false) return false;
  if (prog.includes('AZUL') && filtros.azul === false) return false;

  // 2. Sem filtro geográfico → liberado
  const origens = filtros.origens || [];
  const destinos = filtros.destinos || [];
  if (origens.length === 0 && destinos.length === 0) return true;

  // 3. Quebra o trecho em origem e destino
  const partes = (trecho || '').toUpperCase().split('-');
  const origemVoo = (partes[0] || '').trim();
  const destinoVoo = (partes[1] || '').trim();

  const temVolta = det.includes('VOLTA');

  // 4. Sentido normal: Origem → Destino
  const passaNormal = bateComFiltro(origemVoo, origens) && bateComFiltro(destinoVoo, destinos);

  // 5. Sentido invertido (volta): Destino → Origem
  const passaInvertido = temVolta
    ? bateComFiltro(destinoVoo, origens) && bateComFiltro(origemVoo, destinos)
    : false;

  return passaNormal || passaInvertido;
}

// ─────────────────────────────────────────────────────────────────────────────
// RECEPÇÃO DO PUSH — filtra antes de notificar
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data = {};
  try {
    const json = event.data.json();
    data = json.data ?? json;
  } catch (_) { return; }

  if (data.action !== 'SYNC_ALERTS') return;

  const programa = data.programa ?? 'Oportunidade VIP';
  const trecho = data.trecho ?? '';
  const detalhes = data.detalhes ?? '';
  const id = data.id ?? `alerta-${Date.now()}`;

  event.waitUntil(
    lerFiltros().then((filtros) => {
      // Aplica os filtros do usuário antes de mostrar qualquer notificação
      if (!passaNoFiltro(filtros, programa, trecho, detalhes)) {
        console.log(`[SW] 🚫 Notificação bloqueada pelos filtros: ${programa} | ${trecho}`);
        return; // Descarta silenciosamente
      }

      console.log(`[SW] ✅ Notificação aprovada: ${programa} | ${trecho}`);
      return self.registration.showNotification(`✈️ ${programa}`, {
        body: trecho,
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        tag: id,
        renotify: true,
        data: data,
      });
    })
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// CLIQUE NA NOTIFICAÇÃO → foca a aba ou abre nova com trecho para blur dourado
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data ?? {};
  const trecho = data.trecho ?? '';
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