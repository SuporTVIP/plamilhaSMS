import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert.dart';
import 'discovery_service.dart';

/// Define e gerencia as preferências de filtragem de alertas para o usuário.
///
/// Permite filtrar por companhia aérea, origens e destinos.
class UserFilters {
  // Configurações
  static const String _keyUserFilters = 'USER_FILTERS_V2';

  /// Se alertas da LATAM devem ser exibidos.
  bool latamAtivo;

  /// Se alertas da SMILES devem ser exibidos.
  bool smilesAtivo;

  /// Se alertas da AZUL devem ser exibidos.
  bool azulAtivo;

  /// Lista de origens permitidas (ex: ["GRU - SÃO PAULO"]).
  List<String> origens;

  /// Lista de destinos permitidos (ex: ["JFK - NEW YORK"]).
  List<String> destinos;

  /// Construtor padrão com configurações de fábrica.
  UserFilters({
    this.latamAtivo = true,
    this.smilesAtivo = true,
    this.azulAtivo = true,
    this.origens = const [],
    this.destinos = const [],
  });

  // 🚀 FUNÇÃO DE NORMALIZAÇÃO: Remove acentos, espaços extras e padroniza o caso.
  static String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .trim()
        .toUpperCase();
  }

  /// Carrega as preferências salvas anteriormente no armazenamento local.
  ///
  /// Retorna as preferências padrão se não houver dados salvos.
  static Future<UserFilters> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_keyUserFilters);

    if (jsonStr == null)  return UserFilters();

    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      return UserFilters(
        latamAtivo: data['latam'] ?? true,
        smilesAtivo: data['smiles'] ?? true,
        azulAtivo: data['azul'] ?? true,
        origens: List<String>.from(data['origens'] ?? []),
        destinos: List<String>.from(data['destinos'] ?? []),
      );
    } catch (e) {
      print("⚠️ Erro ao carregar filtros: $e");
      return UserFilters();
    }
  }

  /// Salva as preferências atuais no armazenamento local (SharedPreferences).
  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode({
      'latam': latamAtivo,
      'smiles': smilesAtivo,
      'azul': azulAtivo,
      'origens': origens,
      'destinos': destinos,
    });
    await prefs.setString(_keyUserFilters, jsonStr);
  }

  /// Verifica se um programa e trecho específicos passam no filtro.
  bool passaNoFiltroBasico(String programa, String trecho, {String? detalhes}) {
    final String programaUpper = programa.toUpperCase(); //aqui não precisa normalizar pq os nomes das cias aéreas são bem padronizados, mas deixo em upper case pra garantir que a comparação seja case-insensitive
    final String trechoUpper = trecho.toUpperCase(); //aqui também não precisa normalizar pq os trechos são bem padronizados (ex: "GRU - JFK"), mas deixo em upper case pra garantir que a comparação seja case-insensitive
    final String detalhesUpper = _normalizar(detalhes ?? ""); //aqui sim normalizo porque os detalhes podem vir de fontes variadas e conter acentos, espaços extras, etc. Normalizar ajuda a garantir que a comparação seja mais robusta e menos suscetível a variações de formatação.

    // 1. Filtro por Companhia Aérea (Obrigatório, nunca fura)
    if (programaUpper.contains("LATAM") && !latamAtivo) return false;
    if (programaUpper.contains("SMILES") && !smilesAtivo) return false;
    if (programaUpper.contains("AZUL") && !azulAtivo) return false;

    // Se o usuário não configurou nenhum filtro geográfico, tá liberado!
    if (origens.isEmpty && destinos.isEmpty) return true;

    // 2. Descobre se o voo tem Volta
    bool temVolta = detalhesUpper.contains("VOLTA");

    // 3. Quebra o trecho no meio para saber quem é a Origem e quem é o Destino (Ex: "JPA - GRU")
    List<String> partesTrecho = trechoUpper.split('-');
    String origemVoo = partesTrecho.isNotEmpty ? partesTrecho[0].trim() : trechoUpper;
    String destinoVoo = partesTrecho.length > 1 ? partesTrecho[1].trim() : trechoUpper;

    // 4. Testa a viagem no Sentido Normal (Ida: Origem -> Destino)
    bool passaSentidoNormal = _bateComFiltro(origemVoo, origens) && _bateComFiltro(destinoVoo, destinos);

    // 5. 🚀 A MÁGICA DA VOLTA! Testa o Sentido Invertido (Volta: Destino -> Origem)
    bool passaSentidoInvertido = false;
    if (temVolta) {
      // Se tem volta, o passageiro vai sair do "Destino" e pousar na "Origem"
      passaSentidoInvertido = _bateComFiltro(destinoVoo, origens) && _bateComFiltro(origemVoo, destinos);
    }

    // Se passar em QUALQUER UM dos dois sentidos, toca a sirene!
    return passaSentidoNormal || passaSentidoInvertido;
  }

  bool _bateComFiltro(String localVoo, List<String> listaUsuario) {
    if (listaUsuario.isEmpty) return true;

    // 🚀 Normalizamos o local do voo para comparação
    final String localVooNorm = _normalizar(localVoo);

    for (String filtroUsuario in listaUsuario) {
      List<String> partesUsu = filtroUsuario.split(' - ');
      
      // 🚀 Normalizamos cada parte do filtro salvo pelo usuário
      String iata = _normalizar(partesUsu[0]);
      String cidade = partesUsu.length > 1 ? _normalizar(partesUsu[1]) : "";

      if (localVooNorm.contains(iata) || (cidade.isNotEmpty && localVooNorm.contains(cidade))) {
        return true;
      }
    }
    return false;
  }

 /// Verifica se um [Alert] completo atende aos critérios.
  bool alertaPassaNoFiltro(Alert alerta) {
    return passaNoFiltroBasico(
      alerta.programa, 
      alerta.trecho, 
      detalhes: alerta.detalhes,
    );
  }
}

/// Serviço para gerenciamento da lista de aeroportos disponíveis no sistema.
///
/// Mantém cache diário para performance e fallback de segurança.
class AeroportoService {
  // Configurações
  static const String _keyAeroCache = "AERO_LIST_CACHE";
  static const String _keyLastSync = "AERO_LAST_SYNC_DATE";

  // Dependências
  final DiscoveryService _discovery = DiscoveryService();

  /// Obtém a lista atualizada de aeroportos, priorizando cache local diário.
  Future<List<String>> getAeroportos() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String hoje = DateTime.now().toIso8601String().split('T')[0];
    final String? ultimaBusca = prefs.getString(_keyLastSync);

    // Cache local: Evita rede em chamadas subsequentes no mesmo dia.
    if (ultimaBusca == hoje && prefs.containsKey(_keyAeroCache)) {
      try {
        final List<dynamic> cachedList = jsonDecode(prefs.getString(_keyAeroCache)!);
        return List<String>.from(cachedList);
      } catch (e) {
        print("⚠️ Erro ao decodificar cache de aeroportos: $e");
      }
    }

    return await _syncAeroportosServer(prefs, hoje);
  }

  /// Realiza a sincronização da lista de aeroportos com o servidor remoto.
  Future<List<String>> _syncAeroportosServer(SharedPreferences prefs, String hoje) async {
    try {
      final DiscoveryConfig? config = await _discovery.getConfig();
      if (config == null || !config.isActive) {
        return _getFallback(prefs);
      }

      final Uri uriBase = Uri.parse(config.gasUrl);
      final Uri uriSegura = uriBase.replace(queryParameters: {'action': 'SYNC_AEROPORTOS'});

      final http.Response response = await http.get(uriSegura).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200 && response.body.trim().startsWith('{')) {
        final Map<String, dynamic> body = jsonDecode(response.body);

        if (body['status'] == 'success') {
          final List<String> aeroportos = List<String>.from(body['data']);

          if (aeroportos.isNotEmpty) {
            await prefs.setString(_keyAeroCache, jsonEncode(aeroportos));
            await prefs.setString(_keyLastSync, hoje);
            return aeroportos;
          }
        }
      }
    } catch (e) {
      print("⚠️ Falha na rede ao sincronizar aeroportos: $e");
    }

    return _getFallback(prefs);
  }

  /// Retorna uma lista de aeroportos padrão se o servidor estiver inacessível e não houver cache.
  List<String> _getFallback(SharedPreferences prefs) {
    if (prefs.containsKey(_keyAeroCache)) {
      try {
        return List<String>.from(jsonDecode(prefs.getString(_keyAeroCache)!));
      } catch (e) {
        print("⚠️ Falha ao ler fallback do cache: $e");
      }
    }

    return [
      "GRU - São Paulo",
      "CGH - São Paulo",
      "VCP - São Paulo",
      "GIG - Rio de Janeiro",
      "SDU - Rio de Janeiro",
      "BSB - Brasília"
    ];
  }
}
