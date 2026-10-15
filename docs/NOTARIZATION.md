# Assinatura e notarização da distribuição oficial

A partir da 0.1.8, releases oficiais exigem **Developer ID Application**, Hardened Runtime, timestamp seguro, aprovação do serviço de notarização Apple e tickets anexados ao app e ao DMG. A assinatura Ed25519 do atualizador permanece como verificação adicional do catálogo e do download.

## Credenciais locais

A chave privada Developer ID, a credencial de notarização e a chave Ed25519 permanecem no Keychain do mantenedor. O processo não exporta essas chaves, não envia certificados privados ao GitHub e não usa credenciais de publicação em workflows de pull requests. O repositório contém scripts genéricos, permissões do app, dependências fixadas e chaves públicas.

Certificado público, identidade do desenvolvedor, Team ID e comprovante de notarização são inspecionáveis na assinatura distribuída. São metadados públicos, não permitem assinar outro aplicativo. Arquivos `.p12`, `.pfx`, chaves privadas, senhas, perfis locais e logs de submissão não pertencem ao Git ou aos pacotes.

## Build local e release

Sem `DANTE_SIGN_IDENTITY`, `scripts/build.sh` continua produzindo um build ad hoc para desenvolvimento. Para distribuição, configure **localmente** as duas variáveis abaixo; não coloque credenciais em `.env` versionado nem no comando:

```sh
export DANTE_SIGN_IDENTITY="IDENTIDADE_DEVELOPER_ID_DO_SEU_KEYCHAIN"
export DANTE_NOTARY_PROFILE="NOME_DO_SEU_PERFIL_LOCAL"
bash scripts/release.sh /caminho/absoluto/changelog.md
```

Essas variáveis referenciam uma identidade e um perfil existentes; não carregam a chave privada nem a senha. O perfil é criado previamente pelo fluxo seguro do `notarytool`/Keychain. A release exige checkout público limpo, revisado e enviado a `main`. Não assinar código de terceiros ou de PRs sem revisão.

Etapas individuais para diagnóstico:

```sh
export DANTE_BUILD_DIR=build/release-VERSAO
bash scripts/build.sh
bash scripts/test-app.sh
python3 packaging/notarize.py --app "$DANTE_BUILD_DIR/Dante Live.app"
bash scripts/package.sh
python3 packaging/notarize.py --dmg dist/Dante-Live-VERSAO-local.dmg
```

O app e todos os seus componentes Mach-O recebem a mesma identidade. A validação de bibliotecas continua habilitada; não são adicionadas exceções de memória executável, injeção DYLD ou depuração. Câmera e entrada de áudio têm as permissões necessárias, e o macOS ainda exige consentimento do usuário. Plugins externos de câmera/áudio podem precisar de análise específica; não há garantia de compatibilidade universal.

O app é enviado em ZIP temporário à Apple, aprovado e recebe o ticket. O DMG é montado depois disso, assinado, enviado e recebe seu próprio ticket. `stapler validate`, `codesign` e Gatekeeper precisam passar. Só então o publicador assina os **bytes finais** com Ed25519, publica e confere os assets e atualiza o catálogo. Qualquer alteração posterior exige repetir os passos pertinentes; não sobrescrever versões publicadas.

O ID da submissão, resultado e log ficam somente no diretório de build ignorado. Se houver timeout, inspecione a submissão registrada antes de reenviar; a Apple pode continuar processando. Falhas não são publicadas como sucesso.

## Forks e colaboradores

Um fork recebe o código, nunca as credenciais do mantenedor. Pode compilar ad hoc ou usar sua própria conta Apple e certificado para notarizar sua distribuição. Para publicar atualizações próprias, deve definir identidade de aplicativo, URLs/repositório e par de chaves Ed25519 próprios. Copiar a chave pública oficial não concede capacidade de assinar releases oficiais. O binário oficial inalterado mantém sua assinatura; modificar seus bytes invalida a assinatura correspondente.

## Limites da aprovação

Notarização verifica requisitos de segurança e assinatura; não comprova ausência de bugs, desempenho, compatibilidade com todo dispositivo ou execução em Intel físico. As validações funcionais e pendências continuam em STATUS.md. A mudança de assinatura pode fazer o macOS solicitar novamente uma autorização de acesso a dispositivos ou ao Keychain; não apague projetos nem redefina permissões indiscriminadamente.

Referências: [Developer ID](https://developer.apple.com/developer-id/), [notarização](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) e [Sparkle](https://sparkle-project.org/documentation/).
