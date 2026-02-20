import 'dart:convert';

class Alert {
  final String id;
  final String mensagem;
  final String programa;
  final DateTime data;
  final String? link;
  
  // 🚀 Nossos Metadados Extraídos
  final String trecho;
  final String dataIda;
  final String dataVolta;
  final String milhas;
  final String valorFabricado;
  final String valorEmissao;

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
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    // Tenta ler a string JSON que veio da Coluna G
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
    );
  }
}