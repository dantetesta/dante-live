# Dependências e licenças

O código do Dante Live é disponibilizado sob GNU GPL versão 2 ou posterior. Preserve os avisos próprios de cada componente e as modificações aplicadas ao código de terceiros.

| Componente | Referência / uso |
|---|---|
| OBS Studio / libobs | 32.2.2, commit `ba2f32bdf791005443988a4955e963663e16b1ed`; captura, composição, áudio, filtros, encoders e saídas |
| Sparkle | 2.10.0, commit `eef1a539a373c1f1a320624b1130fc5de7b2e100`; licença MIT e avisos incluídos; atualização assinada, download e instalação/reinício nativos |
| SIMDe | v0.8.2, commit `71fd833d9666141edcd1d3c109a80e228303d8d7`; licença MIT |
| obs-deps | 2026-07-15, commit `8683107a02300923abe4f293920f4b5edc8cb624`; receitas e avisos de dependências |
| FFmpeg, x264 e bibliotecas de codecs | Runtime oficial da referência OBS; composição e opções do build precisam ser consideradas no inventário de redistribuição |
| FreeType/CoreText | Renderização de texto; descoberta de fontes pelo sistema Apple |
| RNNoise/SpeexDSP | Processamento de áudio nos módulos disponíveis |
| Frameworks Apple | SwiftUI, AppKit, AVFoundation, Metal, ScreenCaptureKit, Core Audio, VideoToolbox e Security |

As referências detalhadas estão em `packaging/source-lock.json`; a seleção de módulos está em `packaging/modules.txt`. As receitas de aquisição, patches e compilação fazem parte do repositório.

## Modificações próprias

O módulo RTMP manual é recompilado sem o atualizador de catálogo de serviços. O patch `packaging/patches/obs-outputs-connect-lifecycle.patch` modifica o ciclo de vida da thread de conexão para coordenar seu encerramento. Esses arquivos devem acompanhar a fonte correspondente do produto.

## Publicação de código e distribuição binária

Cada release binária inclui um ZIP separado com as fontes Dante, OBS, SIMDe, receitas obs-deps e 18 dependências fixadas, incluindo submódulos necessários. `SOURCE-MANIFEST.json` registra commits, URLs, hashes e destinos de extração. O DMG contém apenas runtime e avisos legais.

Na versão 0.1.3, as 14 bibliotecas dinâmicas de terceiros correspondem aos UUIDs do SDK obs-deps fixado nas duas arquiteturas. O FFmpeg reportou n8.1.2, GPLv3 ou posterior e as opções de codecs previstas nas receitas. O conjunto binário inclui componentes GPLv3 ou posterior; o código próprio Dante permanece GPLv2 ou posterior. As licenças individuais são preservadas.

O aplicativo e módulos modificados foram recompilados. A reconstrução integral de todas as dependências e a reprodução bit a bit **não foram executadas**. Receitas, patches, fontes e instruções estão no ZIP; `packaging/SOURCE-ACQUISITION.txt` descreve o procedimento e seus limites. O ZIP antigo `source-preparation` continua parcial e não é publicado nas releases.

Browser CEF, plugins profissionais e câmera virtual ainda exigem implementação e análise próprias. Não há promessa de compatibilidade com todos os plugins do OBS.

0.1.6: integração YouTube usa Foundation/URLSession, Network (retorno OAuth local), CryptoKit/Security (PKCE, entropia e Keychain) e UniformTypeIdentifiers. Frameworks do macOS, sem biblioteca externa ou cliente Google embutido. Contratos oficiais e configuração em [YOUTUBE.md](YOUTUBE.md).

0.1.7: SDK Sparkle fixado por SHA-256 em `packaging/sparkle-lock.json`; fontes exatas acompanham o ZIP separado. Runtime não sandboxed inclui framework, Autoupdate e Updater.app, sem ferramentas de assinatura, headers ou serviços XPC opcionais. Nenhuma chave privada é distribuída.

## Incremento 0.1.9 — editor, áudio e convidados

Implementados: cartões de fontes e biblioteca visual YouTube, ⌘F, crop/pan com Option, máscaras GPU com enquadramento, aparência persistente e mixer estéreo vertical RMS/pico/hold. Convidados por token: até dois navegadores, câmera/tela/microfone separados, admissão, revogação e retorno mix-minus. Ver [GUESTS.md](GUESTS.md) para operação e limites.

Fontes: Sources/App/GuestModel.swift, GuestHTTPServer.swift, GuestsView.swift, Sources/Bridge/DanteGuestRTC.mm, Sources/GuestWeb. Dependências e hashes em packaging/guests-lock.json. LiveKitWebRTC BSD/patentes e empacotamento MIT; cloudflared Apache 2.0 e Go com licenças transitivas. Ambos Universal 2; helper recompilado com deployment target 14.0 porque o binário upstream exigia 15.0.

Aceitação: dois peers Chrome com mídia sintética real, fontes e medidores libobs, retorno espectral sem própria voz, revogação; segurança HTTP/token/origem; máscaras verificadas em pixels GPU. Não equivale a teste de redes NAT distintas, TURN, Safari, duas horas, Intel físico ou macOS 14 real. TURN não provisionado; Quick Tunnel temporário sem SLA. As pendências históricas de convidados passam a ser estes limites, não ausência total da funcionalidade.
