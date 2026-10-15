# Dependências e licenças

O código do Dante Live é disponibilizado sob GNU GPL versão 2 ou posterior. Preserve os avisos próprios de cada componente e as modificações aplicadas ao código de terceiros.

| Componente | Referência / uso |
|---|---|
| OBS Studio / libobs | 32.2.2, commit `ba2f32bdf791005443988a4955e963663e16b1ed`; captura, composição, áudio, filtros, encoders e saídas |
| SIMDe | v0.8.2, commit `71fd833d9666141edcd1d3c109a80e228303d8d7`; licença MIT |
| obs-deps | 2026-07-15, commit `8683107a02300923abe4f293920f4b5edc8cb624`; receitas e avisos de dependências |
| FFmpeg, x264 e bibliotecas de codecs | Runtime oficial da referência OBS; composição e opções do build precisam ser consideradas no inventário de redistribuição |
| FreeType/fontconfig | Renderização de texto e descoberta de fontes |
| RNNoise/SpeexDSP | Processamento de áudio nos módulos disponíveis |
| Frameworks Apple | SwiftUI, AppKit, AVFoundation, Metal, ScreenCaptureKit, Core Audio, VideoToolbox e Security |

As referências detalhadas estão em `packaging/source-lock.json`; a seleção de módulos está em `packaging/modules.txt`. As receitas de aquisição, patches e compilação fazem parte do repositório.

## Modificações próprias

O módulo RTMP manual é recompilado sem o atualizador de catálogo de serviços. O patch `packaging/patches/obs-outputs-connect-lifecycle.patch` modifica o ciclo de vida da thread de conexão para coordenar seu encerramento. Esses arquivos devem acompanhar a fonte correspondente do produto.

## Publicação de código e distribuição binária

Este repositório contém o código local, as receitas e as referências de dependências. Os runtimes de terceiros são obtidos separadamente. A publicação deste repositório não significa que a coleta integral da fonte correspondente de cada biblioteca binária já esteja concluída.

Antes de distribuir aplicativos/instaladores, é necessário fechar o inventário de fontes, versões, flags, patches e licenças que corresponda exatamente aos binários entregues. O ZIP gerado por `scripts/package.sh` é preparação parcial, identificado como tal. Não o apresente como cumprimento integral desse trabalho.

Browser CEF, plugins profissionais e câmera virtual ainda exigem implementação e análise próprias. Não há promessa de compatibilidade com todos os plugins do OBS.
