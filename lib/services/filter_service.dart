import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/alert.dart';
import 'discovery_service.dart';

class UserFilters {
  bool latamAtivo;
  bool smilesAtivo;
  bool azulAtivo;
  List<String> origens; // 🚀 Agora é uma Lista de Strings
  List<String> destinos;

  UserFilters({
    this.latamAtivo = true,
    this.smilesAtivo = true,
    this.azulAtivo = true,
    this.origens = const [],
    this.destinos = const [],
  });

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode({
      'latam': latamAtivo,
      'smiles': smilesAtivo,
      'azul': azulAtivo,
      'origens': origens,
      'destinos': destinos,
    });
    await prefs.setString('USER_FILTERS_V2', jsonStr); // Mudei a chave pra V2 para zerar a memória antiga
  }

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

  // 🚀 O MOTOR DE MATCH INTELIGENTE
  bool alertaPassaNoFiltro(Alert alerta) {
    String prog = alerta.programa.toUpperCase();
    String trechoAlerta = alerta.trecho.toUpperCase();
    
    if (prog.contains("LATAM") && !latamAtivo) return false;
    if (prog.contains("SMILES") && !smilesAtivo) return false;
    if (prog.contains("AZUL") && !azulAtivo) return false;

    // Função interna para testar se uma cidade/IATA bate com o trecho do alerta
    bool testaMatch(List<String> locais) {
      if (locais.isEmpty) return true; // Se não tem filtro, passa
      
      for (String local in locais) {
        // Exemplo local: "GRU - SAO PAULO"
        List<String> partes = local.split(' - ');
        String iata = partes[0].trim().toUpperCase();
        String cidade = partes.length > 1 ? partes[1].trim().toUpperCase() : "";

        // Testa se o alerta contém "GRU" OU "SAO PAULO"
        if (trechoAlerta.contains(iata) || (cidade.isNotEmpty && trechoAlerta.contains(cidade))) {
          return true; // Match encontrado!
        }
      }
      return false;
    }

    if (!testaMatch(origens)) return false;
    if (!testaMatch(destinos)) return false;

    return true; 
  }
}

// ==========================================
// 🚀 NOVO SERVIÇO: GERENTE DE AEROPORTOS (Busca e Cache Diário)
// ==========================================
class AeroportoService {
  static const String _keyAeroCache = "AERO_LIST_CACHE";
  static const String _keyLastSync = "AERO_LAST_SYNC_DATE";
  final DiscoveryService _discovery = DiscoveryService();

  Future<List<String>> getAeroportos() async {
    final prefs = await SharedPreferences.getInstance();
    String hoje = DateTime.now().toIso8601String().split('T')[0];
    String? ultimaBusca = prefs.getString(_keyLastSync);

    // Se já buscou hoje e tem cache, retorna do celular (Ultra rápido)
    if (ultimaBusca == hoje && prefs.containsKey(_keyAeroCache)) {
      try {
        List<dynamic> cachedList = jsonDecode(prefs.getString(_keyAeroCache)!);
        return List<String>.from(cachedList);
      } catch (e) {}
    }

    // Se não, vai na internet buscar
    return await _syncAeroportosServer(prefs, hoje);
  }

  Future<List<String>> _syncAeroportosServer(SharedPreferences prefs, String hoje) async {
    try {
      final config = await _discovery.getConfig();
      if (config == null || !config.isActive) return _getFallback(prefs);

      final uriBase = Uri.parse(config.gasUrl);
      final uriSegura = uriBase.replace(queryParameters: {'action': 'SYNC_AEROPORTOS'});

      final response = await http.get(uriSegura).timeout(const Duration(seconds: 15));
      
      // 🚀 ESPIÃO DE DEBUG: Assim você sempre saberá o que o servidor respondeu
      print("📡 Resposta Aeroportos: ${response.body}");

      if (response.statusCode == 200 && response.body.trim().startsWith('{')) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success') {
          List<String> aeros = List<String>.from(body['data']);
          if (aeros.isNotEmpty) {
            // Salva o Cache
            await prefs.setString(_keyAeroCache, jsonEncode(aeros));
            await prefs.setString(_keyLastSync, hoje);
            return aeros;
          }
        }
      }
    } catch (e) {
      print("Erro ao buscar aeroportos: $e");
    }
    return _getFallback(prefs);
  }

  List<String> _getFallback(SharedPreferences prefs) {
    if (prefs.containsKey(_keyAeroCache)) {
      return List<String>.from(jsonDecode(prefs.getString(_keyAeroCache)!));
    }
    return ["GRU - São Paulo", "CGH - São Paulo", "VCP - São Paulo", "GIG - Rio de Janeiro", "SDU - Rio de Janeiro", "BSB - Brasília"];
  }
}