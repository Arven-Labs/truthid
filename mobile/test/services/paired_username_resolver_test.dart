import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart';

import 'package:truthid_mobile/services/blockchain_service.dart';
import 'package:truthid_mobile/services/local_storage_service.dart';
import 'package:truthid_mobile/services/paired_username_resolver.dart';

class MockLocalStorageService extends Mock implements LocalStorageService {}

class MockBlockchainService extends Mock implements BlockchainService {}

void main() {
  late MockLocalStorageService mockStorage;
  late MockBlockchainService mockBlockchain;

  setUpAll(() {
    registerFallbackValue(BigInt.zero);
  });

  setUp(() {
    mockStorage = MockLocalStorageService();
    mockBlockchain = MockBlockchainService();
  });

  test('username já em cache: devolve sem consultar a chain', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => 'alice');

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, 'alice');
    verifyNever(() => mockBlockchain.getUsernameForIdentity(any()));
  });

  test('username null: resolve on-chain e persiste', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenAnswer((_) async => 'alice');
    when(() => mockStorage.savePairedUsername('alice')).thenAnswer((_) async {});

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, 'alice');
    verify(() => mockStorage.savePairedUsername('alice')).called(1);
  });

  test('resolução on-chain devolve null: não persiste nada', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenAnswer((_) async => null);

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, isNull);
    verifyNever(() => mockStorage.savePairedUsername(any()));
  });

  test('falha transiente de RPC: devolve null em vez de propagar', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenThrow(Exception('log scan timed out'));

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
    );

    expect(result, isNull);
    verifyNever(() => mockStorage.savePairedUsername(any()));
  });

  test('scan que nunca termina: estoura o teto e devolve null', () async {
    when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
    // Future que nunca completa = scan de identidade antiga preso em RPC lento.
    when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
        .thenAnswer((_) => Completer<String?>().future);

    final result = await resolvePairedUsername(
      storage: mockStorage,
      blockchain: mockBlockchain,
      identityId: '1',
      scanTimeout: const Duration(milliseconds: 50),
    );

    expect(result, isNull);
    verifyNever(() => mockStorage.savePairedUsername(any()));
  });

  group('verifyAndSavePairedUsername', () {
    IdentityInfo info(int id) => IdentityInfo(
          id: BigInt.from(id),
          controller: EthereumAddress.fromHex(
              '0x1234567890123456789012345678901234567890'),
        );

    test('id on-chain bate com o pareado: salva sem o @', () async {
      when(() => mockBlockchain.getIdentityByUsername('alice'))
          .thenAnswer((_) async => info(1));
      when(() => mockStorage.savePairedUsername('alice')).thenAnswer((_) async {});

      final r = await verifyAndSavePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        username: '  @alice ',
      );

      expect(r, UsernameVerification.confirmed);
      verify(() => mockStorage.savePairedUsername('alice')).called(1);
    });

    test('username de outra identidade: não salva', () async {
      when(() => mockBlockchain.getIdentityByUsername('bob'))
          .thenAnswer((_) async => info(2));

      final r = await verifyAndSavePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        username: 'bob',
      );

      expect(r, UsernameVerification.wrongIdentity);
      verifyNever(() => mockStorage.savePairedUsername(any()));
    });

    test('username inexistente: notFound, não salva', () async {
      when(() => mockBlockchain.getIdentityByUsername('ghost'))
          .thenAnswer((_) async => null);

      final r = await verifyAndSavePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        username: 'ghost',
      );

      expect(r, UsernameVerification.notFound);
      verifyNever(() => mockStorage.savePairedUsername(any()));
    });

    test('campo vazio: notFound sem consultar a chain', () async {
      final r = await verifyAndSavePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        username: ' @ ',
      );

      expect(r, UsernameVerification.notFound);
      verifyNever(() => mockBlockchain.getIdentityByUsername(any()));
    });

    test('RPC falhou: unreachable, não salva', () async {
      when(() => mockBlockchain.getIdentityByUsername('alice'))
          .thenThrow(Exception('all RPCs failed'));

      final r = await verifyAndSavePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        username: 'alice',
      );

      expect(r, UsernameVerification.unreachable);
      verifyNever(() => mockStorage.savePairedUsername(any()));
    });
  });

  group('caminho direto por device (deviceAddress)', () {
    const device = '0xAC2CA4113bb88f1F2A4a03F7a6bcDAc4e9762bc3';

    test('acha pelo device: salva e NÃO varre o histórico', () async {
      when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
      when(() => mockBlockchain.getUsernameForDevice(device))
          .thenAnswer((_) async => 'alice');
      when(() => mockStorage.savePairedUsername('alice')).thenAnswer((_) async {});

      final result = await resolvePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        deviceAddress: device,
      );

      expect(result, 'alice');
      verify(() => mockStorage.savePairedUsername('alice')).called(1);
      verifyNever(() => mockBlockchain.getUsernameForIdentity(any()));
    });

    test('caminho direto não achou: cai no scan por eventos', () async {
      when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
      when(() => mockBlockchain.getUsernameForDevice(device))
          .thenAnswer((_) async => null);
      when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
          .thenAnswer((_) async => 'alice');
      when(() => mockStorage.savePairedUsername('alice')).thenAnswer((_) async {});

      final result = await resolvePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        deviceAddress: device,
      );

      expect(result, 'alice');
      verify(() => mockBlockchain.getUsernameForIdentity(BigInt.one)).called(1);
    });

    test('caminho direto lança: também cai no scan', () async {
      when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
      when(() => mockBlockchain.getUsernameForDevice(device))
          .thenThrow(Exception('rpc down'));
      when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
          .thenAnswer((_) async => 'alice');
      when(() => mockStorage.savePairedUsername('alice')).thenAnswer((_) async {});

      final result = await resolvePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
        deviceAddress: device,
      );

      expect(result, 'alice');
    });

    test('sem deviceAddress: nem tenta o caminho direto', () async {
      when(() => mockStorage.getPairedUsername()).thenAnswer((_) async => null);
      when(() => mockBlockchain.getUsernameForIdentity(BigInt.one))
          .thenAnswer((_) async => 'alice');
      when(() => mockStorage.savePairedUsername('alice')).thenAnswer((_) async {});

      await resolvePairedUsername(
        storage: mockStorage,
        blockchain: mockBlockchain,
        identityId: '1',
      );

      verifyNever(() => mockBlockchain.getUsernameForDevice(any()));
    });
  });
}
