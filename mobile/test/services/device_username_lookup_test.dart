import 'package:flutter_test/flutter_test.dart';
import 'package:truthid_mobile/services/blockchain_service.dart';

void main() {
  const device = '0xAC2CA4113bb88f1F2A4a03F7a6bcDAc4e9762bc3';
  const deviceAddedTopic =
      '0x7f83670760ccf6df0d685c2ffa624d26ca757940c78361fcbbf187253055f951';
  String topicFor(String addr) =>
      '0x${addr.toLowerCase().replaceFirst('0x', '').padLeft(64, '0')}';

  group('estimateBlockAtTimestamp', () {
    test('mesmo timestamp do bloco mais recente: é o próprio bloco', () {
      expect(
        BlockchainService.estimateBlockAtTimestamp(
            latestBlock: 1000, latestTimestamp: 5000, timestamp: 5000),
        1000,
      );
    });

    test('Base produz 1 bloco a cada 2 s: 600 s atrás = 300 blocos', () {
      expect(
        BlockchainService.estimateBlockAtTimestamp(
            latestBlock: 1000, latestTimestamp: 5000, timestamp: 4400),
        700,
      );
    });

    test('número ímpar de segundos arredonda pra baixo (no máximo 1 bloco)', () {
      expect(
        BlockchainService.estimateBlockAtTimestamp(
            latestBlock: 1000, latestTimestamp: 5000, timestamp: 4999),
        1000,
      );
    });

    test('caso real medido na mainnet: bloco 52787374', () {
      // latest 52787579 em ts 1792364505 (205 blocos = 410 s depois do
      // registro, addedAt 1792364095).
      expect(
        BlockchainService.estimateBlockAtTimestamp(
            latestBlock: 52787579, latestTimestamp: 1792364505, timestamp: 1792364095),
        52787374,
      );
    });
  });

  group('controllerFromReceiptLogs', () {
    final smartAccount = '0xaa45c750286a6f686f051130064e8295dd6eda05';

    test('devolve o emissor do DeviceAdded deste device', () {
      final logs = [
        {
          'address': '0x937702CBABDab0EEBD1A29f0a7A658FeF4582543',
          'topics': ['0xdeadbeef', topicFor('0x1')],
        },
        {
          'address': smartAccount,
          'topics': [deviceAddedTopic, topicFor(device)],
        },
      ];

      final controller = BlockchainService.controllerFromReceiptLogs(logs, device);

      expect(controller!.hexEip55.toLowerCase(), smartAccount);
    });

    test('ignora DeviceAdded de OUTRO device (registro em lote)', () {
      final logs = [
        {
          'address': smartAccount,
          'topics': [deviceAddedTopic, topicFor('0x1234567890123456789012345678901234567890')],
        },
      ];

      expect(BlockchainService.controllerFromReceiptLogs(logs, device), isNull);
    });

    test('ignora logs com outro topic0 e logs sem topic1', () {
      final logs = [
        {'address': smartAccount, 'topics': ['0xdeadbeef', topicFor(device)]},
        {'address': smartAccount, 'topics': [deviceAddedTopic]},
      ];

      expect(BlockchainService.controllerFromReceiptLogs(logs, device), isNull);
    });

    test('sem logs: null', () {
      expect(BlockchainService.controllerFromReceiptLogs([], device), isNull);
    });

    test('compara o endereço sem diferenciar maiúsculas (checksum)', () {
      final logs = [
        {'address': smartAccount, 'topics': [deviceAddedTopic, topicFor(device.toLowerCase())]},
      ];

      expect(
        BlockchainService.controllerFromReceiptLogs(logs, device.toUpperCase().replaceFirst('0X', '0x')),
        isNotNull,
      );
    });
  });
}
