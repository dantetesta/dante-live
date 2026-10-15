# Atualizações dentro do aplicativo

Disponível a partir da versão **0.1.7**. Instale esta primeira versão arrastando o aplicativo do DMG para Aplicativos, com o Dante encerrado. Não é necessário desinstalar ou apagar projetos. Versões anteriores não conseguem se atualizar sozinhas porque ainda não contêm o atualizador.

Depois disso, use **Dante Live → Verificar atualizações…**, próximo de Sobre. O app também consulta o catálogo ao abrir, respeitando a preferência de verificações automáticas do Sparkle. Uma nova versão mostra o changelog e pede a decisão de baixar/instalar; não há instalação silenciosa. O aplicativo salva o projeto antes de encerrar e reinicia na versão instalada. Execute a partir de uma pasta gravável, normalmente Aplicativos, e não de dentro do DMG.

## Proteção da live e dos dados

A verificação manual é adiada durante transmissão, preparação, confirmação, contagem regressiva ou operação pendente no YouTube. Se a live começar enquanto o download já está em andamento, a instalação fica pendente. Encerrar a live sozinho **não reinicia** o programa: use novamente Verificar atualizações para confirmar. Falha ao salvar o projeto bloqueia a instalação.

O atualizador substitui o bundle do aplicativo. Projetos e preferências continuam em Application Support, e credenciais continuam no Keychain. Não altera OBS ou seus perfis. Cópias de validação que usam diretório de projeto separado têm atualizações desativadas.

## Catálogo e confiança

Sparkle **2.10.0**, fixado por SHA-256 em `packaging/sparkle-lock.json`, fornece a interface nativa, download, instalação e reinício. O app exige assinatura Ed25519 do catálogo e do DMG antes de extrair. A chave pública está no Info.plist; a chave privada fica no Keychain do mantenedor, conta `com.dantetesta.DanteLive.updates`. Ela nunca entra no Git, DMG, fontes ou logs. Mantenha uma cópia de recuperação dessa chave em armazenamento seguro fora do repositório; não gere uma chave diferente para uma release comum.

O catálogo público é `https://raw.githubusercontent.com/dantetesta/dante-live/main/updates/appcast.xml`. Os DMGs, fontes e checksums ficam nas Releases, com URLs versionadas. Todos os itens deste canal são experimentais até que a política de estabilidade seja alterada explicitamente.

Assinatura Ed25519 de atualização e notarização Apple são verificações distintas. A partir da **0.1.8**, a publicação oficial exige Developer ID, Hardened Runtime e notarização do app e do DMG, além de Ed25519. A chave Ed25519 existente é preservada na transição da 0.1.7. Veja [NOTARIZATION.md](NOTARIZATION.md). Intel físico, macOS 14 real e instalação em máquina limpa ainda precisam de validação.

## Publicar a próxima versão

1. Aumentar versão e build no Info.plist, escrever changelog e revisar o código no checkout público `main`.
2. Compilar, testar, empacotar e disponibilizar as fontes correspondentes usando [RELEASING.md](RELEASING.md).
3. O publicador verifica a chave, o conteúdo real do DMG, arquiteturas e assinatura do app; assina DMG e catálogo localmente.
4. Publica os assets como rascunho e compara os hashes remotos. Só então publica a release e envia o novo catálogo/changelog e botão do README.

Não sobrescrever assets de versões publicadas. Se o push do catálogo falhar, os downloads permanecem acessíveis; revisar e enviar o commit pendente antes de anunciar atualização interna. Não reexecutar a criação da mesma release. GitHub e caches podem demorar a servir o catálogo novo.

## Evidência e limites

Testes cobrem bloqueio durante live/preparação/contagem, retomada explícita, falha de persistência, callbacks duplicados, ordenação numérica de builds e validação de metadados. Um aplicativo nativo de teste isolado usa o mesmo controlador Sparkle e a mesma barreira de instalação, com identidade, projeto, chave e servidor loopback próprios. O teste de download/instalação/reinício não usa captura nem transmissão real. `Tests/UpdaterHarness.swift` é ferramenta de desenvolvimento e nunca integra o DMG.

Referências: [Sparkle](https://sparkle-project.org/documentation/), [publicação](https://sparkle-project.org/documentation/publishing/), [customização](https://sparkle-project.org/documentation/customization/).
