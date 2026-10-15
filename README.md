<div align="center">

# Dante Live

**Um estúdio de produção audiovisual com experiência nativa de Mac.**

Cenas, captura, áudio, gravação e transmissão ao vivo — com interface própria em Swift e o motor audiovisual do OBS Studio.

<!-- current-download:start -->
[![Baixar Dante Live para Mac](https://img.shields.io/badge/BAIXAR_PARA_MAC-v0.1.4-18B7C7?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/dantetesta/dante-live/releases/download/v0.1.4/Dante-Live-0.1.4-macOS-universal.dmg)

**macOS 14+ · Apple Silicon e Intel · Universal 2**
Versão experimental **0.1.4**. Assinatura local (ad hoc), sem notarização Apple. [Notas e fontes](https://github.com/dantetesta/dante-live/releases/tag/v0.1.4).
<!-- current-download:end -->

[Começar pelo código](docs/BUILD.md) · [Estado do projeto](docs/STATUS.md) · [Contribuir](CONTRIBUTING.md) · [Propor uma melhoria](https://github.com/dantetesta/dante-live/issues)

</div>

---

## Por que estamos construindo o Dante Live

Produzir uma live exige cuidar de muitas coisas ao mesmo tempo: enquadramento, cenas, áudio, arquivos, convidados e conexão. Queremos tornar esse trabalho mais claro e confortável para quem usa Mac, com uma interface organizada e controles que respeitem o jeito de trabalhar do sistema.

O Dante Live combina **SwiftUI e AppKit** na interface com **libobs e componentes audiovisuais do OBS Studio** no motor. Reaproveitamos o que já resolve captura, composição e codificação, enquanto construímos uma experiência própria e evoluímos os componentes com base em testes e medições.

O projeto é aberto a quem queira escrever código, testar equipamentos, melhorar a experiência, documentar ou ajudar a definir o que torna um estúdio realmente útil no dia a dia.

## Plataforma

O código atual é exclusivo para **macOS 14.0 Sonoma ou superior**:

- **Apple Silicon:** arm64, a partir do M1, nos Macs compatíveis com o sistema.
- **Intel:** x86_64, nos Macs oficialmente compatíveis com macOS 14 ou posterior.
- Build Universal 2 para o aplicativo e dependências essenciais.

Não há versões para Windows, Linux, iPhone ou iPad. A interface principal não usa Qt, Electron ou Tauri.

O deployment target 14.0 e as slices Universal 2 foram inspecionados; testes em **Intel físico e macOS 14 real ainda estão pendentes**. O backend Metal upstream é experimental e exclusivo Apple Silicon; Intel utiliza OpenGL na implementação atual.

## O que já existe

A versão **0.1.4** amplia a base funcional, em estágio experimental, com funcionalidades reais:

- Cenas e fontes com criação, duplicação, renomeação, ordenação por arrasto, visibilidade e bloqueio.
- Propriedades de fontes aplicadas automaticamente: seleções imediatas e campos digitados com pausa de 300 ms.
- Menu de contexto com propriedades em modal, filtros, renomear, ocultar, bloquear, transformar, ordenar e remover.
- Preview, seleção de elementos, arrasto, redimensionamento proporcional, crop, rotação, ajuste ao canvas e centralização.
- Integração de tela, janela, câmera, microfone, mídia, imagem, cor e texto por módulos selecionados da libobs; a validação varia por fonte e dispositivo.
- Painel de câmera com dispositivos, presets, formato/FPS e prévia da fonte.
- Mixer com volume, mute, medidores e filtros disponíveis no catálogo real.
- Modo estúdio, corte/fade, gravação MKV, transmissão manual RTMP/RTMPS e replay buffer.
- Presets de **1080p, 1440p/QHD e 2160p/4K**, com 30/60 FPS e configuração de bitrate orientada pelo upload.
- Projeto JSON com salvamento atômico, cópia anterior e recuperação; chave RTMP opcional no Keychain.

O envio ao YouTube pela conexão manual foi testado pelo mantenedor. Isso ainda não inclui login Google nem edição de título, descrição, capa ou visibilidade pelo aplicativo.

**Há limitações conhecidas:** a URL RTMP ainda não é restaurada automaticamente; não existem conexões nomeadas; há relato de lag no preview/modo estúdio; o editor avançado e a cobertura de dispositivos estão incompletos. Consulte o [estado detalhado](docs/STATUS.md).

## Para onde queremos levar o projeto

### Produção mais simples

Evoluir a organização das fontes com painéis recolhíveis, grupos, seleção múltipla, alinhamento e atalhos. A ordenação por arrasto e as propriedades em modal já estão disponíveis. Persistir conexões e configurações de forma previsível, mantendo credenciais protegidas.

### Convidados por link

Permitir gerar um convite temporário para a pessoa abrir no navegador, informar o nome, escolher câmera e microfone e compartilhar a tela. No Dante, cada mídia deve aparecer como fonte independente, com controle de volume, mute e visibilidade.

A proposta usa WebRTC com conexão direta quando possível e TURN como alternativa. Reconexão, retorno de áudio sem eco, acesso por token e custos de infraestrutura precisam fazer parte da implementação. **Esse recurso ainda não está disponível no código publicado.**

### Desempenho demonstrável

Medir CPU, GPU, memória, tempo por quadro, perdas e sincronização; reduzir cópias e trabalho redundante quando houver evidência de benefício. Não tratamos a troca de linguagem como ganho automático, nem redução de qualidade como otimização equivalente.

### Cobertura audiovisual

Avançar na equivalência funcional com os recursos macOS do OBS, incluindo editor, filtros, saídas, browser, câmera virtual e integrações auditadas individualmente. A prioridade atual de transmissão é a conexão manual já existente com o YouTube. Outras redes e transmissão simultânea ficam para etapas posteriores.

## Como colaborar

Procuramos contribuições em **Swift/SwiftUI/AppKit, C/C++/Objective-C++, Metal, áudio, vídeo, WebRTC, testes, acessibilidade e documentação**. Também precisamos de quem teste em Macs Intel e Apple Silicon, com diferentes câmeras, microfones e capturadoras.

Uma contribuição útil pode ser pequena: reproduzir um bug, tornar uma mensagem compreensível, corrigir um controle por teclado ou medir um cenário de produção. Abra uma [issue](https://github.com/dantetesta/dante-live/issues) com o problema e o comportamento esperado; para código, siga o [guia de contribuição](CONTRIBUTING.md) e envie um pull request.

## Compilar

O build requer um Mac, ferramentas Apple, Python 3, Git e o runtime oficial **OBS Studio 32.2.2**. Ainda há dependência de binários OBS pré-compilados; não é uma reconstrução integral de todas as bibliotecas a partir das fontes.

```sh
git clone https://github.com/dantetesta/dante-live.git
cd dante-live
env DANTE_BUILD_DIR=build/dev bash scripts/build.sh
```

Leia [BUILD.md](docs/BUILD.md) para configurar a origem do OBS, rodar os testes e entender os limites do empacotamento. O build é separado da instalação e dos perfis do OBS. Não substitua uma instalação usada em produção para testar o projeto.

## Organização do código

| Diretório | Responsabilidade |
|---|---|
| `Sources/App` | Interface nativa, modelo de projeto, propriedades, presets e persistência |
| `Sources/Bridge` | Contrato C e integração Objective-C++ com libobs |
| `Tests` | Verificações de motor, persistência, editor e ciclo de vida |
| `scripts` | Aquisição das referências, build, testes e pacote local |
| `packaging` | Dependências fixadas, patches, auditoria e assinatura local |
| `docs` | Arquitetura, build, estado e licenças |

Mais detalhes em [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Estado de distribuição

O botão no topo baixa o **DMG experimental corrente**. Abra o DMG, arraste Dante Live para Aplicativos e execute-o quando os dispositivos estiverem disponíveis. Se o macOS bloquear a abertura por falta de notarização, use **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**, após conferir a origem do download. Não desative o Gatekeeper globalmente.

As [Releases](https://github.com/dantetesta/dante-live/releases) incluem o instalador, fontes correspondentes com dependências fixadas e SHA-256. A assinatura é **ad hoc**, sem Developer ID ou notarização. Testes prolongados e compatibilidade física Intel/macOS 14 permanecem pendentes. Os builds não substituem o OBS instalado.

Para mantenedores: `scripts/release.sh` compila, testa, empacota e publica uma versão experimental com fontes e checksums; o botão é atualizado para a versão publicada. Veja [RELEASING.md](docs/RELEASING.md).

## Licença e créditos

Dante Live é disponibilizado sob a **GNU General Public License, versão 2 ou posterior**. Consulte [LICENSE](LICENSE) e [DEPENDENCIES.md](docs/DEPENDENCIES.md).

O projeto utiliza o trabalho do [OBS Project e seus colaboradores](https://github.com/obsproject/obs-studio), além das bibliotecas de terceiros identificadas no inventário. A referência atual é **OBS Studio 32.2.2**, commit `ba2f32bdf791005443988a4955e963663e16b1ed`.

Dante Live é um projeto independente; não é uma versão oficial nem possui afiliação anunciada com o OBS Project. A interface e a identidade visual são próprias.
