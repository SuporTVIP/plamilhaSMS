import 'dart:convert';

/// Representa um alerta de emissão de passagem aérea.
///
/// Esta classe contém todos os dados necessários para exibir um alerta de emissão,
/// incluindo informações de trecho, milhas, valores e metadados.
class Alert {
  /// Identificador único do alerta.
  final String id;

  /// Mensagem completa do alerta.
  final String mensagem;

  /// Programa de fidelidade (ex: LATAM, SMILES, AZUL).
  final String programa;

  /// Data e hora da captura do alerta.
  final DateTime data;

  /// Link externo para a emissão ou detalhes adicionais.
  final String? link;

  /// Trecho da viagem (ex: GRU-JFK).
  final String trecho;

  /// Data de ida da viagem.
  final String dataIda;

  /// Data de volta da viagem (se aplicável).
  final String dataVolta;

  /// Quantidade de milhas necessária para a emissão.
  final String milhas;

  /// Valor fabricado calculado para a milha.
  final String valorFabricado;

  /// Valor total estimado da emissão.
  final String valorEmissao;

  /// Valor de mercado (balcão) para comparação.
  final String valorBalcao;

  /// Detalhes adicionais sobre a emissão.
  final String detalhes;

  /// Construtor padrão para a classe [Alert].
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

  /// Cria uma instância de [Alert] a partir de um mapa JSON.
  ///
  /// O parâmetro [json] deve conter as chaves retornadas pela API do GAS.
  /// Metadados são processados separadamente a partir da string JSON no campo 'metadados'.
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

  /// Converte a instância de [Alert] em um mapa JSON para persistência local.
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
}
