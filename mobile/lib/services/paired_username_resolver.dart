import 'dart:async';

import 'blockchain_service.dart';
import 'local_storage_service.dart';

// Extraído do achado real da Sessão 135 (ultrareview): a lógica de "o
// celular já está pareado (identityId persistido), mas o @username nunca
// resolveu — tenta de novo on-chain antes de desistir" tinha sido
// copiada quase igual entre wallet_screen.dart e
// vault_edit_approval_screen.dart, e nunca chegou em mais 3 telas
// (sign_request_approval_screen.dart, sessions_screen.dart,
// vault_screen.dart) que sofrem do mesmo bug: `getUsernameForIdentity`
// (scan de log on-chain) pode falhar uma vez de forma transiente e, sem
// retry, o username nunca mais persiste — travando qualquer tela que
// dependa dele.
//
// Função livre (não um método de LocalStorageService) de propósito —
// LocalStorageService é só um wrapper chave-valor, sem dependência de
// BlockchainService; misturar as duas nela criaria um acoplamento que não
// existe hoje em nenhum outro lugar do projeto.
Future<String?> resolvePairedUsername({
  required LocalStorageService storage,
  required BlockchainService blockchain,
  required String identityId,
  Duration scanTimeout = kUsernameScanTimeout,
}) async {
  final cached = await storage.getPairedUsername();
  if (cached != null) return cached;

  try {
    // O scan de `IdentityCreated` pode levar muitos minutos pra uma identidade
    // antiga (milhares de chunks de eth_getLogs em RPCs públicos que limitam
    // esse método) — sem teto, toda tela que depende do username ficava num
    // spinner sem fim. Estourou o tempo: devolve null e o usuário pode
    // informar o @username à mão (`verifyAndSavePairedUsername`).
    final resolved = await blockchain
        .getUsernameForIdentity(BigInt.parse(identityId))
        .timeout(scanTimeout);
    if (resolved != null) {
      await storage.savePairedUsername(resolved);
    }
    return resolved;
  } catch (_) {
    // Falha transiente (RPC fora do ar, chunk específico deu timeout) —
    // quem chamou decide o que fazer (mostrar erro, tentar de novo no
    // próximo load, ou só deixar a UI dependente desabilitada).
    return null;
  }
}

/// Teto do scan de logs em `resolvePairedUsername`.
const kUsernameScanTimeout = Duration(seconds: 20);

/// Resultado de `verifyAndSavePairedUsername`.
enum UsernameVerification {
  /// O @username existe on-chain e pertence à identidade pareada: foi salvo.
  confirmed,

  /// O @username existe, mas é de outra identidade (não é a deste device).
  wrongIdentity,

  /// Nenhuma identidade com esse @username.
  notFound,

  /// Não foi possível consultar a chain (rede/RPC).
  unreachable,
}

/// Caminho rápido pra qualquer identidade, não importa a idade: o usuário
/// informa o @username e uma única `eth_call` (`getIdentity(string)`) confere
/// que o id on-chain bate com o da identidade pareada neste device. Só então
/// persiste — nunca grava um username não verificado.
Future<UsernameVerification> verifyAndSavePairedUsername({
  required LocalStorageService storage,
  required BlockchainService blockchain,
  required String identityId,
  required String username,
}) async {
  final handle = username.trim().replaceFirst(RegExp(r'^@'), '');
  if (handle.isEmpty) return UsernameVerification.notFound;

  try {
    final info = await blockchain.getIdentityByUsername(handle);
    if (info == null) return UsernameVerification.notFound;
    if (info.id != BigInt.parse(identityId)) {
      return UsernameVerification.wrongIdentity;
    }
    await storage.savePairedUsername(handle);
    return UsernameVerification.confirmed;
  } catch (_) {
    return UsernameVerification.unreachable;
  }
}
