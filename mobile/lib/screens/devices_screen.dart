import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/l10n_extensions.dart';
import '../services/blockchain_service.dart';
import '../services/device_key_service.dart';
import '../services/local_storage_service.dart';
import '../services/paired_username_resolver.dart';
import '../theme.dart';
import 'create_identity_screen.dart';
import 'pair_device_screen.dart';
import 'show_device_qr_screen.dart';

class DevicesScreen extends StatefulWidget {
  // Injetáveis para testes — em produção usa os defaults.
  final DeviceKeyService? deviceKeyService;
  final LocalStorageService? localStorageService;
  final BlockchainService? blockchainService;

  const DevicesScreen({
    super.key,
    this.deviceKeyService,
    this.localStorageService,
    this.blockchainService,
  });

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final DeviceKeyService _keyService;
  late final LocalStorageService _storage;
  late final BlockchainService _blockchain;

  String? _deviceAddress;
  String? _pairedIdentityId;
  String? _pairedUsername;
  String? _encryptionPubKey;
  bool _isLoading = true;
  // O @username é resolvido em segundo plano: o scan on-chain pode levar muito
  // tempo pra uma identidade antiga, e a tela não pode ficar num spinner até
  // ele acabar. Se não resolver, o usuário informa o @username à mão.
  bool _resolvingUsername = false;
  bool _usernameScanDone = false;
  bool _verifyingUsername = false;
  UsernameVerification? _verifyResult;
  final _usernameCtrl = TextEditingController();

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _keyService = widget.deviceKeyService ?? DeviceKeyService();
    _storage = widget.localStorageService ?? LocalStorageService();
    _blockchain = widget.blockchainService ?? BlockchainService();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _isLoading = true);

    try {
      final address = await _keyService.getDeviceAddress();
      var identityId = await _storage.getPairedIdentityId();

      final device = await _blockchain.getDevice(address);

      if (device != null && !device.revoked) {
        if (identityId == null) {
          // Auto-descoberta: device registrado on-chain mas não salvo localmente.
          identityId = device.identityId.toString();
          await _storage.savePairedIdentity(identityId);
        }
      } else if (identityId != null) {
        // Device revogado ou removido — limpar storage
        await _storage.clearPairedIdentity();
        identityId = null;
      }

      // Só o cache aqui (rápido). A resolução on-chain do username roda em
      // segundo plano abaixo — antes ela era aguardada neste ponto e, pra uma
      // identidade antiga, segurava o spinner por muitos minutos (todas as
      // abas passam por esta tela primeiro).
      final cachedUsername =
          identityId != null ? await _storage.getPairedUsername() : null;

      if (!mounted) return;
      setState(() {
        _deviceAddress = address;
        _pairedIdentityId = identityId;
        _pairedUsername = cachedUsername;
      });

      if (identityId != null && cachedUsername == null) {
        unawaited(_resolveUsernameInBackground(identityId));
      }
    } finally {
      // Sem isto, uma exceção em qualquer passo acima deixava o spinner
      // pra sempre (sem nenhum erro visível no app de release).
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Sempre passa pelo helper compartilhado, não só na auto-descoberta —
  // achado do /code-review high (M8): um identityId já persistido de uma
  // sessão anterior cujo username nunca resolveu nunca era tentado de novo.
  // resolvePairedUsername já cobre cache + teto de tempo + try/catch.
  Future<void> _resolveUsernameInBackground(String identityId) async {
    setState(() {
      _resolvingUsername = true;
      _usernameScanDone = false;
    });
    final username = await resolvePairedUsername(
      storage: _storage,
      blockchain: _blockchain,
      identityId: identityId,
    );
    if (!mounted) return;
    setState(() {
      _resolvingUsername = false;
      _usernameScanDone = true;
      if (username != null) _pairedUsername = username;
    });
  }

  Future<void> _confirmUsername() async {
    final identityId = _pairedIdentityId;
    if (identityId == null || _verifyingUsername) return;
    setState(() {
      _verifyingUsername = true;
      _verifyResult = null;
    });
    final handle = _usernameCtrl.text.trim().replaceFirst(RegExp(r'^@'), '');
    final result = await verifyAndSavePairedUsername(
      storage: _storage,
      blockchain: _blockchain,
      identityId: identityId,
      username: handle,
    );
    if (!mounted) return;
    setState(() {
      _verifyingUsername = false;
      _verifyResult = result;
      if (result == UsernameVerification.confirmed) _pairedUsername = handle;
    });
  }

  Widget _buildUsernameCard() {
    final l10n = context.l10n;
    final error = switch (_verifyResult) {
      UsernameVerification.notFound => l10n.devicesScreenUsernameNotFound,
      UsernameVerification.wrongIdentity => l10n.devicesScreenUsernameWrongIdentity,
      UsernameVerification.unreachable => l10n.devicesScreenUsernameUnreachable,
      _ => null,
    };

    // Ainda procurando automaticamente: só um aviso discreto, sem formulário.
    if (_resolvingUsername && !_usernameScanDone) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.devicesScreenUsernameSearching,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.devicesScreenUsernameTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.devicesScreenUsernameBody,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameCtrl,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirmUsername(),
              decoration: InputDecoration(
                labelText: l10n.devicesScreenUsernameFieldLabel,
                errorText: error,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _verifyingUsername ? null : _confirmUsername,
                child: _verifyingUsername
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.devicesScreenUsernameConfirmButton),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEncryptionKey() async {
    // `getDevicePublicKeyHex()` só deriva a chave crua a partir da já
    // existente device key local — não é segredo novo, é o mesmo valor
    // que `ShowDeviceQrScreen` já mostra pra um device ainda não pareado.
    // Um device já pareado nunca tinha como reexibir esse valor (achado
    // real, P54/Sessão 206): sem ele, não dá pra redistribuir a vault key
    // atual pra este device via `RedistributeVaultKey` (Desktop) sem
    // revogar e parear tudo de novo.
    final key = await _keyService.getDevicePublicKeyHex();
    if (!mounted) return;
    setState(() => _encryptionPubKey = key);
  }

  void _copyEncryptionKey() {
    if (_encryptionPubKey == null) return;
    Clipboard.setData(ClipboardData(text: _encryptionPubKey!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.devicesScreenEncryptionKeyCopiedSnackbar)),
    );
  }

  // Abre a tela que mostra o QR deste device. Quando ela fecha com
  // sucesso (o desktop terminou de registrar), recarrega esta tela pra
  // refletir o novo status — não precisa de GlobalKey: é a própria
  // DevicesScreen que inicia a navegação, então ela mesma recebe o resultado.
  Future<void> _openPairing() async {
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ShowDeviceQrScreen()),
    );
    if (success == true) _reload();
  }

  // Criar identidade 100% pelo Mobile (P68, fatia 1) — reaproveita
  // savePairedIdentity() dentro do fluxo, então já volta pareado, sem
  // precisar de um passo de pareamento separado depois.
  Future<void> _openCreateIdentity() async {
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateIdentityScreen()),
    );
    if (success == true) _reload();
  }

  // Parear um novo device pelo Mobile (P68, fatia 2) — reaproveita a mesma
  // infra WalletConnect da fatia 1. Só faz sentido com uma identidade já
  // pareada neste device (precisa saber o @username pra resolver a smart
  // account que vai autorizar o device escaneado).
  Future<void> _openPairNewDevice() async {
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PairDeviceScreen(username: _pairedUsername!),
      ),
    );
    if (success == true) _reload();
  }

  void _copyAddress() {
    if (_deviceAddress == null) return;
    Clipboard.setData(ClipboardData(text: _deviceAddress!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.devicesScreenAddressCopiedSnackbar)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // RefreshIndicator: habilita o gesto "puxar pra baixo para atualizar"
    // Precisa de um filho que seja scrollável — usamos ListView
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_pairedIdentityId != null && _pairedUsername == null)
            _buildUsernameCard(),

          // ── Card do device ──────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho: ícone + título + chip de status
                  Row(
                    children: [
                      const Icon(Icons.phone_android),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.devicesScreenThisDeviceLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      _pairedIdentityId != null
                          ? Chip(
                              avatar: const Icon(Icons.verified, size: 14, color: AppColors.success),
                              label: Text(_pairedUsername != null
                                  ? context.l10n.devicesScreenUsernameHandle(_pairedUsername!)
                                  : context.l10n.devicesScreenIdentityChipFallback(_pairedIdentityId!)),
                              labelStyle: const TextStyle(color: AppColors.success),
                              backgroundColor: AppColors.successBg,
                              padding: EdgeInsets.zero,
                            )
                          : Chip(
                              label: Text(context.l10n.devicesScreenNotRegisteredChip),
                              backgroundColor: AppColors.surfaceAlt,
                            ),
                    ],
                  ),

                  const Divider(height: 24),

                  // Endereço do device
                  Text(
                    context.l10n.devicesScreenAddressLabel,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _deviceAddress ?? '...',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: _copyAddress,
                        tooltip: context.l10n.devicesScreenCopyAddressTooltip,
                      ),
                    ],
                  ),

                  // Seção de identidade — só aparece se estiver pareado
                  if (_pairedIdentityId != null) ...[
                    const Divider(height: 24),
                    Text(
                      context.l10n.devicesScreenIdentityLabel,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _pairedUsername != null
                          ? context.l10n.devicesScreenUsernameHandle(_pairedUsername!)
                          : context.l10n.devicesScreenIdentityIdFallback(_pairedIdentityId!),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),

                    if (_encryptionPubKey != null) ...[
                      const Divider(height: 24),
                      Text(
                        context.l10n.devicesScreenEncryptionKeyLabel,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _encryptionPubKey!,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: _copyEncryptionKey,
                            tooltip: context.l10n.devicesScreenCopyEncryptionKeyTooltip,
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _showEncryptionKey,
                        icon: const Icon(Icons.key, size: 18),
                        label: Text(context.l10n.devicesScreenShowEncryptionKeyButton),
                      ),
                    ],

                    if (_pairedUsername != null) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: _openPairNewDevice,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: Text(
                            context.l10n.devicesScreenPairNewDeviceButton),
                      ),
                    ],

                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(context.l10n.devicesScreenUnpairDialogTitle),
                            content: Text(
                              context.l10n.devicesScreenUnpairDialogContent,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(context.l10n.devicesScreenCancelButton),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(
                                  context.l10n.devicesScreenUnpairConfirmButton,
                                  style: const TextStyle(color: AppColors.danger),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await _storage.clearPairedIdentity();
                          _reload();
                        }
                      },
                      icon: const Icon(Icons.link_off, size: 18, color: AppColors.danger),
                      label: Text(
                        context.l10n.devicesScreenUnpairButton,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Dica — só aparece se ainda não pareado ──────────────────────
          if (_pairedIdentityId == null) ...[
            const SizedBox(height: 8),
            Card(
              color: AppColors.infoBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.info, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.devicesScreenPairingHintBody,
                            style: const TextStyle(fontSize: 13, color: AppColors.info),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.l10n.devicesScreenPairingHintFooter,
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openPairing,
                icon: const Icon(Icons.qr_code),
                label: Text(context.l10n.devicesScreenShowQrButton),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openCreateIdentity,
                icon: const Icon(Icons.add_circle_outline),
                label: Text(context.l10n.devicesScreenCreateIdentityButton),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
