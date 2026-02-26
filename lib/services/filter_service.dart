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

  /// Carrega as preferências salvas anteriormente no armazenamento local.
  ///
  /// Retorna as preferências padrão se não houver dados salvos.
  static Future<UserFilters> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_keyUserFilters);

    if (jsonStr == null) {
      return UserFilters();
    }

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

  /// Verifica se um [Alert] específico atende aos critérios de filtragem do usuário.
  ///
  /// Realiza match por companhia aérea e trechos (IATA ou cidade).
  bool alertaPassaNoFiltro(Alert alerta) {
    final String programaUpper = alerta.programa.toUpperCase();
    final String trechoUpper = alerta.trecho.toUpperCase();
    
    // Filtro por Companhia Aérea
    if (programaUpper.contains("LATAM") && !latamAtivo) return false;
    if (programaUpper.contains("SMILES") && !smilesAtivo) return false;
    if (programaUpper.contains("AZUL") && !azulAtivo) return false;

    // Filtro Geográfico (Origem e Destino)
    if (!_testaMatch(origens, trechoUpper)) return false;
    if (!_testaMatch(destinos, trechoUpper)) return false;

    return true;
  }

  /// Verifica se o texto do trecho contém algum dos locais filtrados (IATA ou Nome).
  bool _testaMatch(List<String> locais, String trechoAlerta) {
    // Se não houver filtro geográfico configurado, qualquer trecho é válido.
    if (locais.isEmpty) return true;

    for (String local in locais) {
      // Formato local: "GRU - SÃO PAULO"
      final List<String> partes = local.split(' - ');
      final String iata = partes[0].trim().toUpperCase();
      final String cidade = partes.length > 1 ? partes[1].trim().toUpperCase() : "";

      if (trechoAlerta.contains(iata) || (cidade.isNotEmpty && trechoAlerta.contains(cidade))) {
        return true;
      }
    }

    return false;
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
