// Traduz os erros do bundler (Pimlico / ERC-4337) pra uma frase que diz o
// que aconteceu e o que fazer. O bundler devolve códigos como "AA24 signature
// error", que não dizem nada pra quem não conhece o ERC-4337 — o código
// original continua no fim da mensagem pra quem precisar reportar o bug.

const AA_MESSAGES: Record<string, string> = {
  AA10: "The smart account already exists. Try again.",
  AA13: "Creating the smart account failed.",
  AA20: "The smart account is not deployed on this network yet.",
  AA21: "The smart account does not have enough ETH on Base to pay the network fee. Deposit a little ETH into the smart account (Wallet → Deposit) and try again.",
  AA22: "This operation expired or is not valid yet. Try again.",
  AA23: "The smart account rejected the operation while validating it.",
  AA24: "The smart account refused this device's signature. This device is not authorized on your account (or was revoked). Open Manage devices and register this desktop with your owner wallet, then try again.",
  AA25: "Another operation from this account is still pending. Wait a minute and try again.",
  AA26: "The network fee estimate was too low. Try again.",
  AA33: "The fee payment was rejected.",
  AA40: "The operation ran out of gas during validation. Try again.",
  AA41: "The operation ran out of gas during validation. Try again.",
  AA51: "The smart account does not have enough ETH on Base to pay the network fee. Deposit a little ETH into the smart account and try again.",
};

// Aceita o objeto `error` do JSON-RPC ({code, message}) ou qualquer coisa
// serializável; devolve a frase amigável, ou a mensagem crua se o erro não
// for conhecido.
export function describeBundlerError(error: unknown): string {
  const raw =
    typeof error === "object" && error !== null && "message" in error
      ? String((error as { message: unknown }).message)
      : String(error);

  const code = /\bAA\d{2}\b/.exec(raw)?.[0];
  if (code && AA_MESSAGES[code]) {
    return `${AA_MESSAGES[code]} (${code})`;
  }
  if (/api ?key/i.test(raw) && /(invalid|unauthor|forbidden|not found)/i.test(raw)) {
    return `Pimlico rejected your API key. Check it in Settings (⚙) → Transactions (Pimlico). (${raw})`;
  }
  return raw;
}

// Resposta HTTP que não é JSON-RPC (ex.: 401/403 de chave inválida, 429 de
// limite excedido) — antes estourava como "Unexpected token" no response.json().
export function describeBundlerHttpError(status: number): string {
  if (status === 401 || status === 403) {
    return `Pimlico rejected your API key (HTTP ${status}). Check it in Settings (⚙) → Transactions (Pimlico).`;
  }
  if (status === 429) {
    return "Pimlico rate limit reached (HTTP 429). Wait a minute and try again.";
  }
  return `Pimlico returned HTTP ${status}. Try again in a minute.`;
}
