import 'package:flutter_test/flutter_test.dart';

import 'package:PlamilhaSVIP/models/alert.dart';
import 'package:PlamilhaSVIP/services/filter_service.dart';

void prepararCacheParaTeste() {
  // Limpa qualquer sujeira de testes anteriores
  AirportCache.iataToFullName.clear(); 
  
  // "Ensina" o cache com os aeroportos que os testes vão usar
  AirportCache.iataToFullName['GIG'] = 'Rio de Janeiro Galeao';
  AirportCache.iataToFullName['SDU'] = 'Rio de Janeiro Santos Dumont';
  AirportCache.iataToFullName['GRU'] = 'Sao Paulo Guarulhos';
  AirportCache.iataToFullName['CGH'] = 'Sao Paulo Congonhas';
}

void main() {
  prepararCacheParaTeste();
  group('UserFilters - companhia aerea', () {
    test('bloqueia LATAM quando latamAtivo estiver desligado', () {
      final UserFilters filtros = UserFilters(latamAtivo: false);

      final bool resultado = filtros.passaNoFiltroBasico(
        'LATAM PASS',
        'GRU-GIG',
      );

      expect(resultado, isFalse);
    });

    test('permite SMILES quando smilesAtivo estiver ligado', () {
      final UserFilters filtros = UserFilters(smilesAtivo: true);

      final bool resultado = filtros.passaNoFiltroBasico('SMILES', 'GRU-GIG');

      expect(resultado, isTrue);
    });

    test(
      'bloqueia programas da categoria OUTROS quando outrosAtivo estiver desligado',
      () {
        final UserFilters filtros = UserFilters(outrosAtivo: false);

        final bool resultado = filtros.passaNoFiltroBasico(
          'TAP MILES&GO',
          'GRU-LIS',
        );

        expect(resultado, isFalse);
      },
    );
  });

  group('UserFilters - geografia ida', () {
    test('aprova match exato por IATA', () {
      final UserFilters filtros = UserFilters(
        origens: const ['GRU - Sao Paulo'],
      );

      final bool resultado = filtros.passaNoFiltroBasico('LATAM', 'GRU-GIG');

      expect(resultado, isTrue);
    });

    test(
      'aprova match por cidade usando alias de aeroporto da mesma cidade',
      () {
        final UserFilters filtros = UserFilters(
          destinos: const ['SDU - Rio de Janeiro'],
        );

        final bool resultado = filtros.passaNoFiltroBasico('LATAM', 'GRU-GIG');

        expect(resultado, isTrue);
      },
    );

    test('aprova quando nao ha filtros geograficos configurados', () {
      final UserFilters filtros = UserFilters();

      final bool resultado = filtros.passaNoFiltroBasico('LATAM', 'GRU-GIG');

      expect(resultado, isTrue);
    });
  });

  group('UserFilters - trecho invertido', () {
    test('aprova voo de volta quando origem e destino estao invertidos', () {
      final UserFilters filtros = UserFilters(
        origens: const ['GRU - Sao Paulo'],
        destinos: const ['GIG - Rio de Janeiro'],
      );

      final bool resultado = filtros.passaNoFiltroBasico(
        'LATAM',
        'GIG-GRU',
        detalhes: 'Voo de VOLTA',
      );

      expect(resultado, isTrue);
    });

    test(
      'bloqueia trecho invertido quando os detalhes indicam somente ida',
      () {
        final UserFilters filtros = UserFilters(
          origens: const ['GRU - Sao Paulo'],
          destinos: const ['GIG - Rio de Janeiro'],
        );

        final bool resultado = filtros.passaNoFiltroBasico(
          'LATAM',
          'GIG-GRU',
          detalhes: 'Somente IDA',
        );

        expect(resultado, isFalse);
      },
    );
  });

  group('UserFilters - normalizacao', () {
    test('normaliza acentos e preserva o restante do texto', () {
      expect(
        UserFilters.normalizarParaTeste('SAO PAULO - GRU'),
        'SAO PAULO - GRU',
      );
      expect(
        UserFilters.normalizarParaTeste('S\u00C3O PAULO - GRU'),
        'SAO PAULO - GRU',
      );
      expect(
        UserFilters.normalizarParaTeste(
          '\u00E1 \u00E9 \u00ED \u00F3 \u00FA \u00E7',
        ),
        'A E I O U C',
      );
    });
  });

  group('UserFilters - metadados reais', () {
    test('aprova alerta AZUL Recife -> Ribeirao Preto com volta e acentos', () {
      final Alert alerta = _alertaDeMetadados(
        id: '20260324151240298_AZUL_RECIFE_RIBEIRAO_PRETO',
        programa: 'AZUL',
        trecho: 'RECIFE - RIBEIR\u00C3O PRETO',
        detalhes:
            'Disponibilidades - IDA\nJunho: 14\n\nDisponibilidades - VOLTA \nJunho: 21',
      );
      final UserFilters filtros = UserFilters(
        azulAtivo: true,
        origens: const ['RECIFE - Recife'],
        destinos: const ['RAO - Ribeirao Preto'],
      );

      expect(filtros.alertaPassaNoFiltro(alerta), isTrue);
    });

    test('aprova alerta LATAM Macapa -> Orlando com match por cidade', () {
      final Alert alerta = _alertaDeMetadados(
        id: '20260324142208065_LATAM_MACAPA_ORLANDO',
        programa: 'LATAM',
        trecho: 'MACAP\u00C1 - ORLANDO',
        detalhes:
            'Disponibilidades - IDA\nMaio: 6\n\nDisponibilidades - VOLTA\nMaio: 13',
      );
      final UserFilters filtros = UserFilters(
        latamAtivo: true,
        origens: const ['MCP - Macapa'],
        destinos: const ['MCO - Orlando'],
      );

      expect(filtros.alertaPassaNoFiltro(alerta), isTrue);
    });

    test('bloqueia alerta LATAM real quando a companhia esta desativada', () {
      final Alert alerta = _alertaDeMetadados(
        id: '20260324142208065_LATAM_MACAPA_ORLANDO',
        programa: 'LATAM',
        trecho: 'MACAP\u00C1 - ORLANDO',
        detalhes:
            'Disponibilidades - IDA\nMaio: 6\n\nDisponibilidades - VOLTA\nMaio: 13',
      );
      final UserFilters filtros = UserFilters(
        latamAtivo: false,
        origens: const ['MCP - Macapa'],
        destinos: const ['MCO - Orlando'],
      );

      expect(filtros.alertaPassaNoFiltro(alerta), isFalse);
    });

    test('aprova metadado real de volta usando sentido invertido', () {
      final Alert alerta = _alertaDeMetadados(
        id: '20260324151240298_AZUL_RECIFE_RIBEIRAO_PRETO',
        programa: 'AZUL',
        trecho: 'RIBEIR\u00C3O PRETO - RECIFE',
        detalhes:
            'Disponibilidades - IDA\nJunho: 14\n\nDisponibilidades - VOLTA \nJunho: 21',
      );
      final UserFilters filtros = UserFilters(
        azulAtivo: true,
        origens: const ['RECIFE - Recife'],
        destinos: const ['RIBEIRAO PRETO - Ribeirao Preto'],
      );

      expect(filtros.alertaPassaNoFiltro(alerta), isTrue);
    });
  });
}

Alert _alertaDeMetadados({
  required String id,
  required String programa,
  required String trecho,
  required String detalhes,
}) {
  return Alert(
    id: id,
    mensagem: 'alerta de teste',
    programa: programa,
    data: DateTime(2026, 3, 24, 15, 12),
    trecho: trecho,
    detalhes: detalhes,
  );
}
