# Dependências e licenças

O código do Dante Live é disponibilizado sob GNU GPL versão 2 ou posterior. Preserve os avisos próprios de cada componente e as modificações aplicadas ao código de terceiros.

| Componente | Referência / uso |
|---|---|
| OBS Studio / libobs | 32.2.2, commit `ba2f32bdf791005443988a4955e963663e16b1ed`; captura, composição, áudio, filtros, encoders e saídas |
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
