/// Versão "vazia" do gerenciador de janelas para plataformas nativas (Android/iOS).
///
/// Como Android e iOS não possuem o conceito de "fechar aba do navegador",
/// esta implementação não executa nenhuma ação.
void registerWebCloseListener() {
  // No celular, não há abas para fechar, então esta função é um 'noop' (no operation).
}
