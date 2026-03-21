# Milhas Alert (PramilhaSVIP) - Guia Técnico

Bem-vindo à documentação técnica do Milhas Alert. Este documento foi desenhado para ajudar desenvolvedores iniciantes a entenderem a arquitetura e o funcionamento do aplicativo.

## 🚀 Visão Geral

O Milhas Alert é um aplicativo Flutter que monitora emissões de passagens aéreas por milhas em tempo real. Ele se conecta a um servidor (Google Apps Script) que processa dados de planilhas e os entrega via API JSON.

### Analogias para Iniciantes
Se você vem de outras linguagens, aqui está como o Flutter/Dart se compara:
- **Widgets**: São como componentes React ou elementos HTML. Tudo na tela é um Widget.
- **Future**: Igual a uma `Promise` em JavaScript ou `Task` em C#.
- **Stream**: Similar a um `EventEmitter` no Node.js ou `Observable` em RxJS.
- **SharedPreferences**: Funciona como o `localStorage` do navegador.

---

## 🛠️ Arquitetura do Sistema

O app está dividido em quatro pilares principais:

### 1. Modelos (`lib/models/`)
Define a estrutura dos dados. O modelo principal é o `Alert`, que possui um método `factory Alert.fromJson`.
- **Dica**: Pense no `fromJson` como o `json.loads()` do Python, transformando texto bruto em um objeto organizado.

### 2. Serviços (`lib/services/`)
Onde a "mágica" acontece:
- **AlertService**: O "Motor de Tração". Ele usa um **Timer** para rodar um **Polling** (verificação periódica) e envia novos dados através de uma **Stream**.
- **AuthService**: Gerencia a identidade do aparelho (Device ID) e a licença do usuário.
- **DiscoveryService**: Busca dinamicamente a URL do servidor em um Gist do GitHub, permitindo atualizações remotas sem trocar o App na loja.
- **FilterService**: Filtra os alertas com base nas preferências de origem, destino e companhia aérea do usuário.

### 3. Core e Utils (`lib/core/` & `lib/utils/`)
- **Theme**: Centraliza as cores (Cyberpunk Dark) e fontes (IBM Plex Mono).
- **WebWindowManager**: Um exemplo de "Conditional Export", que executa códigos diferentes se o app estiver rodando no navegador ou no celular.

### 4. Interface (`lib/main.dart` & `lib/login_screen.dart`)
- **MainNavigator**: Controla as abas do aplicativo usando um `IndexedStack`.
- **Reatividade**: Usamos o `setState` para avisar ao Flutter que algo mudou e a tela precisa ser redesenhada (similar ao `useState` do React).

---

## 🎨 Layout e Estilização
Para iniciantes, entender como os elementos se organizam é crucial:
- **Flexbox (Row/Column)**: O Flutter usa intensamente o conceito de Flexbox. `Row` e `Column` são os blocos básicos de construção.
- **Espaçamento**: Use `Padding` para preenchimento interno e `SizedBox` para espaços vazios entre componentes.
- **Decoração**: O widget `Container` com a propriedade `decoration: BoxDecoration` permite criar bordas, arredondar cantos e adicionar sombras (como o CSS `border`, `border-radius` e `box-shadow`).

---

## 📡 Fluxo de Dados

1. O app inicia e o `DiscoveryService` localiza o servidor.
2. O `AuthService` valida a licença do usuário.
3. O `AlertService` inicia o loop de monitoramento.
4. Quando novos alertas chegam, eles são passados pelo `FilterService`.
5. Se o alerta passar nos filtros, ele é enviado para a `Stream`.
6. A `AlertsScreen` escuta a `Stream`, toca um som de alerta e adiciona o novo card na tela.

---

## 🧪 Como testar

Para garantir que tudo está funcionando corretamente:
1. Execute `flutter analyze` para verificar erros de sintaxe.
2. Execute `flutter test` para rodar os testes de unidade e widget.
