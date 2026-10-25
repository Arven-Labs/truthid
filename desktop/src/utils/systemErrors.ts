import i18n from "../i18n";

// Erros do Rust/SO chegam como string crua ("Permission denied (os error 13)",
// "Platform secure storage failure: ..."), o que não diz o que fazer. Traduz
// os dois casos que mais travaram o primeiro uso real (P102 itens 4 e 5) e
// deixa o resto passar intacto.
export function describeSystemError(raw: string): string {
  if (/permission denied|os error 13|EACCES/i.test(raw)) {
    return i18n.t("systemErrors.permissionDenied", { raw });
  }
  if (/secret ?service|org\.freedesktop|kwallet|keyring|dbus|platform secure storage|NoStorageAccess/i.test(raw)) {
    return i18n.t("systemErrors.keyringUnavailable", { raw });
  }
  return raw;
}
