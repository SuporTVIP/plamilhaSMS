import 'dart:convert';

/// Representa um alerta de emissão de passagem aérea.
class Alert {
  final String id;
  final String mensagem;
  final String programa;
  final DateTime data;
  final String? link;
  
  final String trecho;
  final String dataIda;
  final String dataVolta;
  final String milhas;
  final String valorFabricado;
  final String valorEmissao;
  final String valorBalcao; 
  final String detalhes; 

  Alert({
    required this.id,
    required this.mensagem,
    required this.programa,
    required this.data,
    this.link,
    this.trecho = "N/A",
    this.dataIda = "N/A",
    this.dataVolta = "N/A",
    this.milhas = "N/A",
    this.valorFabricado = "N/A",
    this.valorEmissao = "N/A",
    this.valorBalcao = "N/A",
    this.detalhes = "N/A",
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> meta = {};
    try {
      if (json['metadados'] != null && json['metadados'].toString().isNotEmpty) {
        meta = jsonDecode(json['metadados']);
      }
    } catch (e) {
      print("Erro ao parsear metadados: $e");
    }

    return Alert(
      id: json['id'].toString(),
      mensagem: json['mensagem'] ?? '',
      programa: json['programa'] ?? 'Desconhecido',
      data: DateTime.parse(json['data']),
      link: json['link'],
      trecho: meta['trecho'] ?? 'N/A',
      dataIda: meta['data_ida'] ?? 'N/A',
      dataVolta: meta['data_volta'] ?? 'N/A',
      milhas: meta['milhas'] ?? 'N/A',
      valorFabricado: meta['valor_fabricado'] ?? 'N/A',
      valorEmissao: meta['valor_emissao'] ?? 'N/A',
      valorBalcao: meta['valor_balcao'] ?? 'N/A',
      detalhes: meta['detalhes'] ?? '',
    );
  }

  // 🚀 AQUI ESTÁ A CORREÇÃO: O toJson() agora está DENTRO da classe Alert
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'programa': programa,
      'trecho': trecho,
      'milhas': milhas,
      'data': data.toIso8601String(),
      'link': link,
      'detalhes': detalhes,
      'mensagem': mensagem,
      'dataIda': dataIda,
      'dataVolta': dataVolta,
      'valorFabricado': valorFabricado,
      'valorEmissao': valorEmissao,
      'valorBalcao': valorBalcao,
    };
  }
} // <--- A classe termina aqui