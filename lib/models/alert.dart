class Alert {
  final String id;
  final String mensagem;
  final String programa;
  final DateTime data;
  final String? link;

  Alert({
    required this.id,
    required this.mensagem,
    required this.programa,
    required this.data,
    this.link,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'].toString(),
      mensagem: json['mensagem'] ?? '',
      programa: json['programa'] ?? 'Desconhecido',
      data: DateTime.parse(json['data']),
      link: json['link'],
    );
  }
}