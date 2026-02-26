import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/alert.dart';

/// Serviço de persistência local utilizando Hive.
///
/// Responsável por salvar e recuperar o histórico de alertas para suportar a
/// estratégia SWR (Stale-While-Revalidate).
class CacheService {
  // Configurações do Cache
  static const String _boxName = 'alerts_cache';

  /// Limite máximo de alertas armazenados para evitar consumo excessivo de armazenamento.
  static const int _maxAlerts = 500;

  /// Inicializa o mecanismo de armazenamento local (Hive).
  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  /// Salva uma lista de alertas no cache local.
  ///
  /// Converte os objetos [Alert] em strings JSON para armazenamento seguro no Hive.
  /// Respeita o limite de [_maxAlerts].
  Future<void> saveAlerts(List<Alert> alerts) async {
    final Box box = Hive.box(_boxName);
    final List<String> dataToSave = alerts
        .take(_maxAlerts)
        .map((alert) => jsonEncode(alert.toJson()))
        .toList();

    await box.put('data', dataToSave);
  }

  /// Recupera a lista de alertas armazenados no cache.
  ///
  /// Retorna uma lista vazia se não houver dados no cache ou se houver falha no parsing.
  List<Alert> loadAlerts() {
    final Box box = Hive.box(_boxName);
    final List<dynamic>? cachedData = box.get('data');

    if (cachedData == null) {
      return [];
    }

    try {
      return cachedData
          .map((jsonStr) => Alert.fromJson(jsonDecode(jsonStr)))
          .toList();
    } catch (e) {
      print("⚠️ Erro ao carregar alertas do cache: $e");
      return [];
    }
  }
}
