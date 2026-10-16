# Compilar e testar

Este guia descreve o código atual: aplicativo desktop SwiftUI/AppKit com libobs e deployment target macOS 14.0. Não há projeto iOS neste repositório.

## Pré-requisitos

- Mac com as ferramentas de desenvolvimento Apple: `xcrun`, `swiftc`, `clang++`, `lipo`, `codesign`, SDK macOS e `iconutil`.
- Git, Python 3.12 ou posterior, Bash e acesso à internet para obter referências fixadas.
- OBS Studio **32.2.2 para Apple Silicon**, usado como origem de runtime. Por padrão, em `/Applications/OBS.app`; `OBS_APP` aceita um caminho alternativo. Não substitua uma instalação em uso: mantenha uma cópia isolada da versão exigida.
- FFmpeg e ffprobe disponíveis no PATH para testes de gravação/áudio e RTMP local.
- Espaço livre para os downloads, dependências e artefatos de compilação.

O fluxo foi usado em Apple Silicon com Command Line Tools e Swift 6.4. A menor versão de compilador compatível ainda não foi determinada. Deployment target do aplicativo e versão do SDK/compilador são requisitos distintos.

## Build

```sh
git clone https://github.com/dantetesta/dante-live.git
cd dante-live
env DANTE_BUILD_DIR=build/dev bash scripts/build.sh
```

Para uma origem OBS isolada:

```sh
env OBS_APP="/caminho/OBS.app" DANTE_BUILD_DIR=build/dev bash scripts/build.sh
```

O script obtém o código OBS 32.2.2 e dependências fixadas, prepara o runtime permitido, compila Swift/Objective-C++, recompila os módulos RTMP modificados, verifica dependências e assina o aplicativo localmente com assinatura ad hoc.

Por padrão, compila `arm64` e `x86_64` e gera `build/dev/Dante Live.app`. A referência Intel é baixada pelo script com verificação de digest. Para um build de desenvolvimento apenas Apple Silicon, use `DANTE_ARCHS=arm64`; esse resultado não é Universal 2.

Nunca compile sobre um bundle que esteja aberto. Use outro `DANTE_BUILD_DIR` durante uma transmissão.

## Testes

```sh
env DANTE_BUILD_DIR=build/dev bash scripts/test-app.sh
env DANTE_APP_PATH="$PWD/build/dev/Dante Live.app" DANTE_TEST_RTMP=1 bash scripts/test-engine.sh
env DANTE_APP_PATH="$PWD/build/dev/Dante Live.app" bash scripts/test-placement.sh
env DANTE_APP_PATH="$PWD/build/dev/Dante Live.app" bash scripts/test-cancellation.sh
```

Os testes usam diretórios isolados, fontes sintéticas e receptores locais. As portas 19350 e 19351 precisam estar livres. Não executam transmissão pública. Leia os exit codes e os resultados gerados em `evidence/runtime/`; esse diretório não deve ser publicado.

As suítes cobrem persistência, geometria, presets, processo de medição com fixtures, composição, gravação, mixer, replay e cancelamento de conexão. Não substituem testes de câmera/microfone físicos, permissões, longas sessões, latência fim a fim ou execução em um Mac Intel.

## Execução

Abra o aplicativo compilado. Câmera, microfone e captura de tela exigem as permissões correspondentes. Use um projeto e dispositivos de teste; respeite equipamentos ocupados por uma live.

Para um projeto isolado de validação, o executável aceita:

```sh
"build/dev/Dante Live.app/Contents/MacOS/DanteLive" --validation-directory "/caminho/absoluto/projeto-de-teste"
```

## Pacotes locais e limites

```sh
env DANTE_BUILD_DIR=build/dev bash scripts/package.sh
```

O empacotamento gera DMG local e um ZIP separado de preparação de fontes. O ZIP é explicitamente parcial: ainda não reúne toda a fonte correspondente de cada dependência binária. As releases públicas usam outro ZIP, completo com as fontes fixadas e descrito em [RELEASING.md](RELEASING.md).

O fluxo atual recompila o aplicativo, a ponte e módulos modificados sobre runtimes oficiais do OBS. Ainda não reconstrói todas as dependências a partir das fontes nem promete reprodução bit a bit. A assinatura é ad hoc, sem Developer ID ou notarização.

## Atualizador nativo

O build baixa e verifica o SDK Sparkle 2.10.0 por hash fixado, incorpora somente framework/helpers de runtime e os assina com o app. Não exige a chave privada de publicação para compilar. A atualização interna fica desativada em execuções com `--validation-directory`. `test-app.sh` também testa a barreira de instalação e o catálogo. A chave privada Ed25519 é necessária somente para publicar um novo catálogo/DMG oficial. Veja [UPDATES.md](UPDATES.md).

## Releases oficiais 0.1.8+

Builds locais sem identidade continuam ad hoc. Para uma release oficial, configure `DANTE_SIGN_IDENTITY` com uma identidade Developer ID Application instalada e `DANTE_NOTARY_PROFILE` com um perfil local existente do notarytool. `scripts/release.sh` exige essas referências e notariza app/DMG antes de publicar. A chave privada e a credencial nunca são copiadas para o Git ou para o instalador. Forks usam credenciais próprias. Veja [NOTARIZATION.md](NOTARIZATION.md).

## Dependências e testes de convidados (0.1.9)

Instale Go com suporte a toolchains automáticos. O build fixa GOTOOLCHAIN=go1.27.2 e compila cloudflared 2026.10.1 para arm64/x86_64, target macOS 14, sem modificar a fonte upstream. A distribuição binária upstream exigia macOS 15. LiveKitWebRTC 150.7871.03 é obtido com SHA-256 fixado em packaging/guests-lock.json. O primeiro build precisa de rede.

`env DANTE_BUILD_DIR=build/dev bash scripts/test-masks.sh` verifica pixels reais da GPU com fontes sintéticas. `scripts/build-guest-tests.sh` compila o harness nativo para o Mac Apple Silicon de desenvolvimento. `Tests/guest-browser.cjs` usa Playwright (dependência somente de QA) e Chrome, com câmeras/telas/áudio sintéticos em dois contextos. O harness aceita caminho absoluto do app e diretório isolado; o modo --public exige estar em um bundle QA com o helper cloudflared e testa HTTPS temporário, nunca transmissão ao YouTube. Não use projeto ou dispositivos de produção nesses testes.
