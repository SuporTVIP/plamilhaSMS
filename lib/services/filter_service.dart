import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert.dart';
import '../utils/logger.dart';
import '../utils/web_filters_sync.dart';
import 'discovery_service.dart';

/// Define e gerencia as preferencias de filtragem de alertas do usuario.
///
/// Permite filtrar por companhia aerea, origens e destinos.
class UserFilters {
  static const String _keyUserFilters = 'USER_FILTERS_V2';

  bool latamAtivo;
  bool smilesAtivo;
  bool azulAtivo;
  bool outrosAtivo;

  final List<String> origens;
  final List<String> destinos;

  UserFilters({
    this.latamAtivo = true,
    this.smilesAtivo = true,
    this.azulAtivo = true,
    this.outrosAtivo = true,
    this.origens = const [],
    this.destinos = const [],
  });

  String _resumoConfiguracao() {
    return 'cias={LATAM:${latamAtivo ? "on" : "off"}, '
        'SMILES:${smilesAtivo ? "on" : "off"}, '
        'AZUL:${azulAtivo ? "on" : "off"}, '
        'OUTROS:${outrosAtivo ? "on" : "off"}} '
        'origens=$origens destinos=$destinos';
  }

  static String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .replaceAll(RegExp('[\u00E1\u00E0\u00E2\u00E3\u00E4]'), 'a')
        .replaceAll(RegExp('[\u00E9\u00E8\u00EA\u00EB]'), 'e')
        .replaceAll(RegExp('[\u00ED\u00EC\u00EE\u00EF]'), 'i')
        .replaceAll(RegExp('[\u00F3\u00F2\u00F4\u00F5\u00F6]'), 'o')
        .replaceAll(RegExp('[\u00FA\u00F9\u00FB\u00FC]'), 'u')
        .replaceAll(RegExp('[\u00E7]'), 'c')
        .trim()
        .toUpperCase();
  }

  static Future<UserFilters> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_keyUserFilters);

    if (jsonStr == null) {
      return UserFilters();
    }

    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      return UserFilters(
        latamAtivo: data['latam'] ?? true,
        smilesAtivo: data['smiles'] ?? true,
        azulAtivo: data['azul'] ?? true,
        outrosAtivo: data['outros'] ?? true,
        origens: List<String>.from(data['origens'] ?? []),
        destinos: List<String>.from(data['destinos'] ?? []),
      );
    } catch (e) {
      // ignore: avoid_print
      print('Erro ao carregar filtros: $e');
      return UserFilters();
    }
  }

  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> filtrosMap = {
      'latam': latamAtivo,
      'smiles': smilesAtivo,
      'azul': azulAtivo,
      'outros': outrosAtivo,
      'origens': origens,
      'destinos': destinos,
    };
    await prefs.setString(_keyUserFilters, jsonEncode(filtrosMap));

    sincronizarFiltrosParaSW(filtrosMap);
  }

  bool passaNoFiltroBasico(
    String programa,
    String trecho, {
    String? detalhes,
    String contexto = 'geral',
    String? alertId,
  }) {
    final String programaUpper = programa.toUpperCase();
    final String trechoUpper = trecho.toUpperCase();
    final String detalhesUpper = _normalizar(detalhes ?? '');
    final String agora = DateTime.now().toIso8601String();
    final String etiqueta = '[FILTER][$contexto]';
    final String alvo = alertId == null
        ? '$programa | $trecho'
        : 'alerta=$alertId | $programa | $trecho';

    AppLogger.log(
      '$etiqueta INICIO quando=$agora alvo=($alvo) detalhes="$detalhes" config=${_resumoConfiguracao()}',
    );

    final bool isAzul = programaUpper.contains('AZUL');
    final bool isLatam = programaUpper.contains('LATAM');
    final bool isSmiles = programaUpper.contains('SMILES');
    final String familiaPrograma = isLatam
        ? 'LATAM'
        : isSmiles
        ? 'SMILES'
        : isAzul
        ? 'AZUL'
        : 'OUTROS';

    AppLogger.log(
      '$etiqueta COMPANHIA detectada=$familiaPrograma programaOriginal="$programa"',
    );

    if (isLatam && !latamAtivo) {
      AppLogger.log(
        '$etiqueta BLOQUEADO onde=companhia quando=$agora porque="LATAM desativada pelo usuario"',
      );
      return false;
    }

    if (isSmiles && !smilesAtivo) {
      AppLogger.log(
        '$etiqueta BLOQUEADO onde=companhia quando=$agora porque="SMILES desativada pelo usuario"',
      );
      return false;
    }

    if (isAzul && !azulAtivo) {
      AppLogger.log(
        '$etiqueta BLOQUEADO onde=companhia quando=$agora porque="AZUL desativada pelo usuario"',
      );
      return false;
    }

    if (!isAzul && !isLatam && !isSmiles && !outrosAtivo) {
      AppLogger.log(
        '$etiqueta BLOQUEADO onde=companhia quando=$agora porque="programa classificado como OUTROS e chave geral esta desligada"',
      );
      return false;
    }

    if (origens.isEmpty && destinos.isEmpty) {
      AppLogger.log(
        '$etiqueta APROVADO onde=geografia quando=$agora porque="nenhum filtro geografico foi configurado"',
      );
      return true;
    }

    final bool temVolta = detalhesUpper.contains('VOLTA');
    final List<String> partesTrecho = trechoUpper.split('-');
    final String origemVoo = partesTrecho.isNotEmpty
        ? partesTrecho[0].trim()
        : trechoUpper;
    final String destinoVoo = partesTrecho.length > 1
        ? partesTrecho[1].trim()
        : trechoUpper;

    AppLogger.log(
      '$etiqueta TRECHO bruto="$trecho" origem="$origemVoo" destino="$destinoVoo" temVolta=$temVolta detalhesNormalizados="$detalhesUpper"',
    );

    final _FilterMatch origemNormal = _bateComFiltro(
      origemVoo,
      origens,
      tipoFiltro: 'origem',
      contexto: contexto,
    );
    final _FilterMatch destinoNormal = _bateComFiltro(
      destinoVoo,
      destinos,
      tipoFiltro: 'destino',
      contexto: contexto,
    );
    final bool passaSentidoNormal = origemNormal.passou && destinoNormal.passou;

    AppLogger.log(
      '$etiqueta SENTIDO onde=ida resultado=${passaSentidoNormal ? "aprovado" : "bloqueado"} '
      'porque="origem:${origemNormal.motivo}; destino:${destinoNormal.motivo}"',
    );

    bool passaSentidoInvertido = false;
    if (temVolta) {
      final _FilterMatch origemInvertida = _bateComFiltro(
        destinoVoo,
        origens,
        tipoFiltro: 'origem-volta',
        contexto: contexto,
      );
      final _FilterMatch destinoInvertido = _bateComFiltro(
        origemVoo,
        destinos,
        tipoFiltro: 'destino-volta',
        contexto: contexto,
      );
      passaSentidoInvertido = origemInvertida.passou && destinoInvertido.passou;
      AppLogger.log(
        '$etiqueta SENTIDO onde=volta resultado=${passaSentidoInvertido ? "aprovado" : "bloqueado"} '
        'porque="origem:${origemInvertida.motivo}; destino:${destinoInvertido.motivo}"',
      );
    } else {
      AppLogger.log(
        '$etiqueta SENTIDO onde=volta resultado=ignorado porque="detalhes nao indicam trecho de volta"',
      );
    }

    final bool aprovado = passaSentidoNormal || passaSentidoInvertido;
    AppLogger.log(
      '$etiqueta FIM resultado=${aprovado ? "APROVADO" : "FILTRADO"} '
      'como=${passaSentidoNormal
          ? "sentido normal"
          : passaSentidoInvertido
          ? "sentido invertido"
          : "nenhum sentido"} '
      'porque="${aprovado ? "atendeu ao menos uma combinacao valida" : "nao atendeu origem/destino configurados"}"',
    );
    return aprovado;
  }

  _FilterMatch _bateComFiltro(
    String localVoo,
    List<String> listaUsuario, {
    required String tipoFiltro,
    required String contexto,
  }) {
    final String etiqueta = '[FILTER][$contexto]';
    if (listaUsuario.isEmpty) {
      AppLogger.log(
        '$etiqueta REGRA onde=$tipoFiltro local="$localVoo" resultado=liberado porque="lista do usuario esta vazia"',
      );
      return const _FilterMatch(true, 'sem restricao configurada');
    }

    final String localVooNorm = _normalizar(localVoo);
    AppLogger.log(
      '$etiqueta REGRA onde=$tipoFiltro localOriginal="$localVoo" localNormalizado="$localVooNorm" candidatos=$listaUsuario',
    );

    for (final String filtroUsuario in listaUsuario) {
      final List<String> partesUsu = filtroUsuario.split(' - ');
      final String iata = _normalizar(partesUsu[0]);
      final String cidade = partesUsu.length > 1
          ? _normalizar(partesUsu[1])
          : '';

      if (localVooNorm.contains(iata) ||
          (cidade.isNotEmpty && localVooNorm.contains(cidade))) {
        final String motivo = cidade.isNotEmpty && localVooNorm.contains(cidade)
            ? 'bateu com cidade "$cidade" do filtro "$filtroUsuario"'
            : 'bateu com IATA "$iata" do filtro "$filtroUsuario"';
        AppLogger.log(
          '$etiqueta REGRA onde=$tipoFiltro filtro="$filtroUsuario" resultado=match porque="$motivo"',
        );
        return _FilterMatch(true, motivo);
      }

      AppLogger.log(
        '$etiqueta REGRA onde=$tipoFiltro filtro="$filtroUsuario" resultado=nao_match '
        'porque="local $localVooNorm nao contem iata $iata nem cidade ${cidade.isEmpty ? "(vazia)" : cidade}"',
      );
    }

    return _FilterMatch(
      false,
      'nenhum filtro configurado para $tipoFiltro combinou com "$localVooNorm"',
    );
  }

  bool alertaPassaNoFiltro(Alert alerta) {
    return passaNoFiltroBasico(
      alerta.programa,
      alerta.trecho,
      detalhes: alerta.detalhes,
      contexto: 'lista-alertas',
      alertId: alerta.id,
    );
  }
}

class _FilterMatch {
  final bool passou;
  final String motivo;

  const _FilterMatch(this.passou, this.motivo);
}

class AeroportoService {
  static const String _keyAeroCache = 'AERO_LIST_CACHE';
  static const String _keyLastSync = 'AERO_LAST_SYNC_DATE';

  final DiscoveryService _discovery = DiscoveryService();

  Future<List<String>> getAeroportos() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String hoje = DateTime.now().toIso8601String().split('T')[0];
    final String? ultimaBusca = prefs.getString(_keyLastSync);

    if (ultimaBusca == hoje && prefs.containsKey(_keyAeroCache)) {
      try {
        final List<dynamic> cachedList = jsonDecode(
          prefs.getString(_keyAeroCache)!,
        );
        return List<String>.from(cachedList);
      } catch (e) {
        // ignore: avoid_print
        print('Erro ao decodificar cache de aeroportos: $e');
      }
    }

    return await _syncAeroportosServer(prefs, hoje);
  }

  Future<List<String>> _syncAeroportosServer(
    SharedPreferences prefs,
    String hoje,
  ) async {
    try {
      final DiscoveryConfig? config = await _discovery.getConfig();
      if (config == null || !config.isActive) {
        return _getFallback(prefs);
      }

      final Uri uriBase = Uri.parse(config.gasUrl);
      final Uri uriSegura = uriBase.replace(
        queryParameters: {'action': 'SYNC_AEROPORTOS'},
      );

      final http.Response response = await http
          .get(uriSegura)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.body.trim().startsWith('{')) {
        final Map<String, dynamic> body = jsonDecode(response.body);

        if (body['status'] == 'success') {
          final List<String> aeroportos = List<String>.from(body['data']);

          if (aeroportos.isNotEmpty) {
            await prefs.setString(_keyAeroCache, jsonEncode(aeroportos));
            await prefs.setString(_keyLastSync, hoje);
            return aeroportos;
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Falha na rede ao sincronizar aeroportos: $e');
    }

    return _getFallback(prefs);
  }

  List<String> _getFallback(SharedPreferences prefs) {
    if (prefs.containsKey(_keyAeroCache)) {
      try {
        return List<String>.from(jsonDecode(prefs.getString(_keyAeroCache)!));
      } catch (e) {
        // ignore: avoid_print
        print('Falha ao ler fallback do cache: $e');
      }
    }

    return const [
      'GRU - S\u00E3o Paulo',
      'CGH - S\u00E3o Paulo',
      'VCP - S\u00E3o Paulo',
      'GIG - Rio de Janeiro',
      'SDU - Rio de Janeiro',
      'BSB - Bras\u00EDlia',
    ];
  }
}
