import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;

import 'storage_pointer.dart';
import 'vault_blob_fetcher.dart';

// Baixa um blob pelo CID a partir de gateways IPFS públicos — usado pelo
// VaultSyncService (13.8) pra buscar o vault cifrado publicado pelo Desktop.
// Só gateways HTTP públicos de leitura, sem autenticação — os provedores de
// pin configurados pelo usuário (Pinata/Filebase/Kubo, etc.) são escopo do
// Desktop (VaultSettings), não precisam ser consultados aqui pra ler.
//
// Etapa 2 da migração de storage (ver project/ROADMAP.md): o Desktop pode
// publicar o blob principal do vault no Arweave em vez do IPFS — o ponteiro
// vem prefixado "ar://<txid>" (auto-descritivo, VaultRegistry.cid é uma
// string opaca, sem mudança de schema). Ler do Arweave não exige
// carteira/cripto nova aqui, é só um GET público contra o gateway — por
// isso o dispatch mora inteiro neste client, sem tocar VaultSyncService nem
// VaultRepository (os dois só chamam fetch(cid)).
class IpfsGatewayClient implements VaultBlobFetcher {
  IpfsGatewayClient({
    this.gateways = const [
      'https://ipfs.io/ipfs/',
      'https://dweb.link/ipfs/',
    ],
    this.arweaveGateway = 'https://arweave.net/',
    this.timeout = const Duration(seconds: 15),
  });

  final List<String> gateways;
  final String arweaveGateway;
  final Duration timeout;

  // Tenta cada gateway em ordem, a primeira resposta 200 vence. Lança se
  // todos falharem (rede, timeout, ou status != 200), com um resumo do que
  // cada gateway retornou.
  @override
  Future<Uint8List> fetch(String cid) async {
    switch (StoragePointerKind.of(cid)) {
      case StoragePointerKind.arweave:
        final txid = cid.substring(StoragePointerKind.arweavePrefix.length);
        // `<gateway>/<txid>` redireciona pra um subdomínio sandbox que,
        // logo depois de uma publicação, responde 200 com corpo vazio por
        // vários minutos (medido: ~10 min) enquanto `<gateway>/raw/<txid>`
        // já serve os mesmos bytes. Tenta as duas rotas antes de desistir.
        final arweaveErrors = <String>[];
        for (final url in ['$arweaveGateway$txid', '${arweaveGateway}raw/$txid']) {
          try {
            return await _fetchFromGateway(url).timeout(timeout);
          } catch (e) {
            arweaveErrors.add('$url: $e');
          }
        }
        throw Exception(
            'The Arweave gateway has not returned the data for $txid yet '
            '(it can take several minutes after publishing): '
            '${arweaveErrors.join('; ')}');
      case StoragePointerKind.git:
        // Conteúdo Git mora num repo, não atrás de um gateway HTTP. Falha
        // logo, em vez de concatenar o ponteiro nas URLs dos gateways IPFS e
        // esperar os timeouts (~30s) de um fetch que nunca funcionaria.
        throw UnsupportedError(
            'Git pointer cannot be fetched from an HTTP gateway: $cid');
      case StoragePointerKind.legacyIpfs:
        break;
    }

    final errors = <String>[];
    for (final gateway in gateways) {
      try {
        return await _fetchFromGateway('$gateway$cid').timeout(timeout);
      } catch (e) {
        errors.add('$gateway: $e');
      }
    }
    throw Exception(
        'All IPFS gateways failed for cid $cid: ${errors.join('; ')}');
  }

  Future<Uint8List> _fetchFromGateway(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      // Um blob de vault nunca é vazio: 200 sem corpo é o gateway ainda sem
      // o dado, e deixar passar só viraria um "hash não bate" mais adiante.
      if (bytes.isEmpty) {
        throw Exception('empty response body');
      }
      return bytes;
    } finally {
      client.close();
    }
  }
}
