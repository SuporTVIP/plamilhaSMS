import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/alert.dart';
import 'discovery_service.dart';

/// Define e gerencia os filtros de preferência do usuário.
class UserFilters {
  bool latamAtivo;
  bool smilesAtivo;
  bool azulAtivo;
  List<String> origens;
  List<String> destinos;

  UserFilters({
    this.latamAtivo = true,
    this.smilesAtivo = true,
    this.azulAtivo = true,
    this.origens = const [],
    this.destinos = const [],
  });

  /// Salva as preferências atuais no armazenamento local.
  ///
  /// Analogia: Converte o objeto em JSON (similar a `json.dumps` em Python)
  /// e salva no localStorage do dispositivo.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode({
      'latam': latamAtivo,
      'smiles': smilesAtivo,
      'azul': azulAtivo,
      'origens': origens,
      'destinos': destinos,
    });
    await prefs.setString('USER_FILTERS_V2', jsonStr);
  }

  /// Carrega as preferências salvas anteriormente.
  static Future<UserFilters> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('USER_FILTERS_V2');
    if (jsonStr == null) return UserFilters();

    try {
      final map = jsonDecode(jsonStr);
      return UserFilters(
        latamAtivo: map['latam'] ?? true,
        smilesAtivo: map['smiles'] ?? true,
        azulAtivo: map['azul'] ?? true,
        origens: List<String>.from(map['origens'] ?? []),
        destinos: List<String>.from(map['destinos'] ?? []),
      );
    } catch (e) {
      return UserFilters();
    }
  }

  /// 🚀 MOTOR DE MATCH INTELIGENTE
  /// Verifica se um alerta específico atende aos critérios escolhidos pelo usuário.
  bool alertaPassaNoFiltro(Alert alerta) {
    String prog = alerta.programa.toUpperCase();
    String trechoAlerta = alerta.trecho.toUpperCase();
    
    // Filtro por Companhia Aérea
    if (prog.contains("LATAM") && !latamAtivo) return false;
    if (prog.contains("SMILES") && !smilesAtivo) return false;
    if (prog.contains("AZUL") && !azulAtivo) return false;

    /// Função interna para verificar se uma cidade ou código IATA está presente no texto do alerta.
    bool testaMatch(List<String> locais) {
      if (locais.isEmpty) return true; // Se o usuário não filtrou origem/destino, tudo passa.
      
      for (String local in locais) {
        // Exemplo local: "GRU - SAO PAULO"
        List<String> partes = local.split(' - ');
        String iata = partes[0].trim().toUpperCase();
        String cidade = partes.length > 1 ? partes[1].trim().toUpperCase() : "";

        // Testa se o alerta contém o código IATA (ex: GRU) OU o nome da cidade (ex: SAO PAULO).
        if (trechoAlerta.contains(iata) || (cidade.isNotEmpty && trechoAlerta.contains(cidade))) {
          return true; // Encontrou um correspondente!
        }
      }
      return false;
    }

    // Verifica se a origem e o destino do alerta batem com os filtros do usuário.
    if (!testaMatch(origens)) return false;
    if (!testaMatch(destinos)) return false;

    return true; 
  }
}

// ==========================================
// 🚀 SERVIÇO: GERENTE DE AEROPORTOS
// ==========================================
/// Responsável por buscar e manter a lista atualizada de aeroportos disponíveis.
class AeroportoService {
  static const String _keyAeroCache = "AERO_LIST_CACHE";
  static const String _keyLastSync = "AERO_LAST_SYNC_DATE";
  final DiscoveryService _discovery = DiscoveryService();

  /// Obtém a lista de aeroportos, priorizando o cache diário para performance.
  Future<List<String>> getAeroportos() async {
    final prefs = await SharedPreferences.getInstance();
    String hoje = DateTime.now().toIso8601String().split('T')[0];
    String? ultimaBusca = prefs.getString(_keyLastSync);

    // Se já buscou hoje, retorna do cache local (Ultra rápido).
    if (ultimaBusca == hoje && prefs.containsKey(_keyAeroCache)) {
      try {
        List<dynamic> cachedList = jsonDecode(prefs.getString(_keyAeroCache)!);
        return List<String>.from(cachedList);
      } catch (e) {}
    }

    // Se for um novo dia ou não tiver cache, busca no servidor.
    return await _syncAeroportosServer(prefs, hoje);
  }

  /// Sincroniza a lista de aeroportos com a planilha/servidor.
  Future<List<String>> _syncAeroportosServer(SharedPreferences prefs, String hoje) async {
    try {
      final config = await _discovery.getConfig();
      if (config == null || !config.isActive) return _getFallback(prefs);

      final uriBase = Uri.parse(config.gasUrl);
      final uriSegura = uriBase.replace(queryParameters: {'action': 'SYNC_AEROPORTOS'});

      final response = await http.get(uriSegura).timeout(const Duration(seconds: 15));
      
      print("📡 Resposta Aeroportos: ${response.body}");

      if (response.statusCode == 200 && response.body.trim().startsWith('{')) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success') {
          List<String> aeros = List<String>.from(body['data']);
          if (aeros.isNotEmpty) {
            // Salva no cache para evitar chamadas de rede desnecessárias.
            await prefs.setString(_keyAeroCache, jsonEncode(aeros));
            await prefs.setString(_keyLastSync, hoje);
            return aeros;
          }
        }
      }
    } catch (e) {
      print("Erro ao buscar aeroportos: $e");
    }
    return _getFallback(prefs); // Se falhar a rede, usa o cache antigo ou uma lista padrão.
  }

  /// Lista padrão de segurança caso o servidor esteja offline e não haja cache.
  List<String> _getFallback(SharedPreferences prefs) {
    if (prefs.containsKey(_keyAeroCache)) {
      return List<String>.from(jsonDecode(prefs.getString(_keyAeroCache)!));
    }
    return ["GRU - São Paulo", "CGH - São Paulo", "VCP - São Paulo", "GIG - Rio de Janeiro", "SDU - Rio de Janeiro", "BSB - Brasília"];
  }
}
