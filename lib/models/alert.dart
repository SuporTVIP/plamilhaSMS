import 'dart:convert';

/// Representa um alerta de emissão de passagem aérea.
///
/// Esta classe funciona como um "Contrato" ou "Data Class" (como em Python ou C#),
/// definindo quais dados uma notificação de milhas deve conter.
class Alert {
  final String id;
  final String mensagem;
  final String programa;
  final DateTime data;
  final String? link;
  
  // 🚀 Metadados Extraídos: Informações detalhadas processadas
  final String trecho;
  final String dataIda;
  final String dataVolta;
  final String milhas;
  final String valorFabricado;
  final String valorEmissao;

  /// Construtor padrão da classe Alert.
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

  /// Constrói uma instância de Alert a partir de um Map (JSON).
  ///
  /// Analogia: Este método funciona como o `json.loads()` do Python ou `JSON.parse()` do JS,
  /// mas com o benefício de transformar os dados brutos em um Objeto Tipado.
  /// No Dart, usamos o padrão 'factory' para criar construtores que retornam instâncias processadas.
  factory Alert.fromJson(Map<String, dynamic> json) {
    // Tenta ler a string JSON que veio da Coluna 'metadados'
    // Map<String, dynamic> no Dart é equivalente a um Dicionário (dict) em Python
    // ou um Objeto literal em JavaScript.
    Map<String, dynamic> meta = {};
    try {
      if (json['metadados'] != null && json['metadados'].toString().isNotEmpty) {
        // jsonDecode transforma uma String JSON em um Dicionário/Mapa.
        meta = jsonDecode(json['metadados']);
      }
    } catch (e) {
      print("Erro ao parsear metadados: $e");
    }

    return Alert(
      id: json['id'].toString(),
      mensagem: json['mensagem'] ?? '',
      programa: json['programa'] ?? 'Desconhecido',
      data: DateTime.parse(json['data']), // Transforma String de data em objeto DateTime (como o datetime.fromisoformat no Python)
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
