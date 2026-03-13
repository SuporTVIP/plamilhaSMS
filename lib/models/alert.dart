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

  //link para emissão direta na agência parceira 
  final String link_agencia;

  final String mensagemBalcao;

  final String taxas;

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
    this.link_agencia = "N/A",
    this.mensagemBalcao = "N/A",
    this.taxas = "N/A",
  });

  // 🚀 TRADUTOR DE DATAS: Converte texto (Março) para número (03)
  static String _padronizarData(String dataBruta) {
    if (dataBruta == 'N/A' || dataBruta.isEmpty) return dataBruta;
    
    String formatada = dataBruta.toLowerCase();
    
    // Dicionário de conversão
    const meses = {
      'janeiro': '01', 'jan': '01',
      'fevereiro': '02', 'fev': '02',
      'março': '03', 'mar': '03',
      'abril': '04', 'abr': '04',
      'maio': '05', 'mai': '05',
      'junho': '06', 'jun': '06',
      'julho': '07', 'jul': '07',
      'agosto': '08', 'ago': '08',
      'setembro': '09', 'set': '09',
      'outubro': '10', 'out': '10',
      'novembro': '11', 'nov': '11',
      'dezembro': '12', 'dez': '12',
    };

    // Substitui as palavras pelos números
    meses.forEach((nome, numero) {
      formatada = formatada.replaceAll(nome, numero);
    });

    // Remove espaços em branco perdidos (ex: "25/ 03" vira "25/03")
    return formatada.replaceAll(RegExp(r'\s+'), '');
  }

  /// Cria uma instância de [Alert] a partir de um mapa JSON.
  ///
  /// O parâmetro [json] deve conter as chaves retornadas pela API do GAS.
  /// Metadados são processados separadamente a partir da string JSON no campo 'metadados'.
// 🚀 2. COMO O APP LÊ DA INTERNET OU DO CACHE
  factory Alert.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> meta = {};
    try {
      // Se a informação veio da Internet, ela terá a chave 'metadados'
      if (json['metadados'] != null && json['metadados'].toString().isNotEmpty) {
        meta = jsonDecode(json['metadados']);
      }
    } catch (e) {
      print("Erro ao parsear metadados: $e");
    }

    String alertaId = meta['id_app']?.toString() ?? json['id']?.toString() ?? 'ID_DESCONHECIDO';

    return Alert(
      id: alertaId,
      mensagem: json['mensagem'] ?? '',
      programa: json['programa'] ?? 'Desconhecido',
      data: DateTime.parse(json['data']).toLocal(),
      link: json['link'],
      // 👇 A MÁGICA: Tenta ler direto do Cache (json) OU da Internet (meta)
      trecho: json['trecho'] ?? meta['trecho'] ?? 'N/A',
      dataIda: _padronizarData(json['dataIda'] ?? meta['data_ida'] ?? 'N/A'),
      dataVolta: _padronizarData(json['dataVolta'] ?? meta['data_volta'] ?? 'N/A'),
      milhas: json['milhas'] ?? meta['milhas'] ?? 'N/A',
      valorFabricado: json['valorFabricado'] ?? meta['valor_fabricado'] ?? 'N/A',
      valorEmissao: json['valorEmissao'] ?? meta['valor_emissao'] ?? 'N/A',
      valorBalcao: json['valorBalcao'] ?? meta['valor_balcao'] ?? 'N/A',
      detalhes: json['detalhes'] ?? meta['detalhes'] ?? '',
      link_agencia: json['link_agencia'] ?? meta['link_agencia'] ?? 'N/A',
      mensagemBalcao: json['mensagemBalcao'] ?? meta['mensagem_balcao'] ?? 'N/A',
      taxas: json['taxas'] ?? meta['taxas'] ?? 'N/A',
    );
  }

  /// Lê um Alert completo diretamente do payload FCM.
  /// Não faz nenhuma chamada de rede. Os dados já vieram no push.
  factory Alert.fromPush(Map<String, dynamic> data) {
    return Alert(
      id: data['id']?.toString() ?? 'FCM_${DateTime.now().millisecondsSinceEpoch}',
      mensagem: data['mensagem']?.toString() ?? '',
      programa: data['programa']?.toString() ?? 'Desconhecido',
      data: DateTime.tryParse(data['data']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      link: data['link']?.toString(),
      trecho: data['trecho']?.toString() ?? 'N/A',
      dataIda: _padronizarData(data['data_ida']?.toString() ?? 'N/A'),
      dataVolta: _padronizarData(data['data_volta']?.toString() ?? 'N/A'),
      milhas: data['milhas']?.toString() ?? 'N/A',
      valorFabricado: data['valor_fabricado']?.toString() ?? 'N/A',
      valorEmissao: data['valor_emissao']?.toString() ?? 'N/A',
      valorBalcao: data['valor_balcao']?.toString() ?? 'N/A',
      detalhes: data['detalhes']?.toString() ?? '',
      link_agencia: data['link_agencia']?.toString() ?? 'N/A',
      mensagemBalcao: data['mensagem_balcao']?.toString() ?? 'N/A',
      taxas: data['taxas']?.toString() ?? 'N/A',
    );
  }

  /// Converte a instância de [Alert] em um mapa JSON para persistência local.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mensagem':       mensagem,
      'programa':       programa,
      'data':           data.toIso8601String(),
      'link':           link,
      'taxas':          taxas,
      'trecho':         trecho,
      'dataIda':        dataIda,
      'dataVolta':      dataVolta,
      'milhas':         milhas,
      'valorFabricado': valorFabricado,
      'valorEmissao':   valorEmissao,
      'valorBalcao':    valorBalcao,
      'detalhes':       detalhes,
      'link_agencia': link_agencia,
      'mensagemBalcao': mensagemBalcao,
    };
  }
}
