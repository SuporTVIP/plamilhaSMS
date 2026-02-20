import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert.dart';

class UserFilters {
  bool latamAtivo;
  bool smilesAtivo;
  bool azulAtivo;
  String origens; // Separado por vírgula (ex: GRU, CGH)
  String destinos;

  UserFilters({
    this.latamAtivo = true,
    this.smilesAtivo = true,
    this.azulAtivo = true,
    this.origens = "",
    this.destinos = "",
  });

  // Salva no celular
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode({
      'latam': latamAtivo,
      'smiles': smilesAtivo,
      'azul': azulAtivo,
      'origens': origens.toUpperCase(),
      'destinos': destinos.toUpperCase(),
    });
    await prefs.setString('USER_FILTERS_V1', jsonStr);
  }

  // Carrega do celular
  static Future<UserFilters> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('USER_FILTERS_V1');
    if (jsonStr == null) return UserFilters();

    try {
      final map = jsonDecode(jsonStr);
      return UserFilters(
        latamAtivo: map['latam'] ?? true,
        smilesAtivo: map['smiles'] ?? true,
        azulAtivo: map['azul'] ?? true,
        origens: map['origens'] ?? "",
        destinos: map['destinos'] ?? "",
      );
    } catch (e) {
      return UserFilters();
    }
  }

  // A LÓGICA DE MATCH (O Motor)
  bool alertaPassaNoFiltro(Alert alerta) {
    String prog = alerta.programa.toUpperCase();
    
    // 1. Filtro de Programa
    if (prog.contains("LATAM") && !latamAtivo) return false;
    if (prog.contains("SMILES") && !smilesAtivo) return false;
    if (prog.contains("AZUL") && !azulAtivo) return false;

    // 2. Filtro de Origem
    if (origens.trim().isNotEmpty) {
      List<String> origensList = origens.split(',').map((e) => e.trim()).toList();
      bool matchOrigem = false;
      for (String o in origensList) {
        if (alerta.trecho.toUpperCase().contains(o)) {
          matchOrigem = true;
          break;
        }
      }
      if (!matchOrigem) return false; // Se digitou origem e não bateu com nenhuma, esconde
    }

    // 3. Filtro de Destino
    if (destinos.trim().isNotEmpty) {
      List<String> destinosList = destinos.split(',').map((e) => e.trim()).toList();
      bool matchDestino = false;
      for (String d in destinosList) {
        if (alerta.trecho.toUpperCase().contains(d)) {
          matchDestino = true;
          break;
        }
      }
      if (!matchDestino) return false; 
    }

    return true; // Se passou por todos os "securitários", tá liberado!
  }
}