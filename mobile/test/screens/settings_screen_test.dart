import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:truthid_mobile/screens/settings_screen.dart';
import 'package:truthid_mobile/services/bundler_config_service.dart';

import '../utils/l10n_test_app.dart';

class MockBundlerConfigService extends Mock implements BundlerConfigService {}

void main() {
  testWidgets(
      'Pinning Providers fica em Configurações como item avançado, com o '
      'aviso de que só serve às aprovações com a extensão', (tester) async {
    final service = MockBundlerConfigService();
    when(() => service.getConfig()).thenAnswer(
        (_) async => const BundlerConfig(apiKey: '', network: 'base'));

    await tester.pumpWidget(wrapForTest(SettingsScreen(configService: service)));
    await tester.pumpAndSettle();

    final tile = find.text('Pinning Providers');
    await tester.scrollUntilVisible(tile, 200,
        scrollable: find.byType(Scrollable).first);
    expect(tile, findsOneWidget);
    expect(
        find.text('Advanced — only used for approvals with the browser extension'),
        findsOneWidget);
  });
}
