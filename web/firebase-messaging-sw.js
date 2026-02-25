importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

const firebaseConfig = {
  apiKey: "AIzaSyAZjnPjOVnbnyzm0pwcUti4aZrWA6F4Fmk",
  authDomain: "plamilhasvipaddondevsadm.firebaseapp.com",
  projectId: "plamilhasvipaddondevsadm",
  storageBucket: "plamilhasvipaddondevsadm.firebasestorage.app",
  messagingSenderId: "1070254866174",
  appId: "1:1070254866174:web:0b8a46e3ff211f685cafaf",
  measurementId: "G-Z2SHWPV2EZ"
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// Lida com mensagens em background (quando a aba está fechada)
messaging.onBackgroundMessage(function(payload) {
  console.log('Push recebido em background:', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png' // Certifique-se que este ícone existe na pasta web/icons
  };
  return self.registration.showNotification(notificationTitle, notificationOptions);
});