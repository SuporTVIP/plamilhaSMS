import 'package:hive_flutter/hive_flutter.dart';
import '../models/alert.dart';
import 'dart:convert';

class CacheService {
  static const String _boxName = 'alerts_cache';
  static const int _maxAlerts = 500; // Limite para não sobrecarregar o storage 

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName); // Abre o "baú" de dados 
  }

  // Salva a lista convertendo os objetos para JSON strings
  Future<void> saveAlerts(List<Alert> alerts) async {
    final box = Hive.box(_boxName);
    final toSave = alerts.take(_maxAlerts).map((e) => jsonEncode(e.toJson())).toList();
    await box.put('data', toSave);
  }

  // Carrega os alertas do cache
  List<Alert> loadAlerts() {
    final box = Hive.box(_boxName);
    final List<dynamic>? cached = box.get('data');
    if (cached == null) return [];
    return cached.map((e) => Alert.fromJson(jsonDecode(e))).toList();
  }
}