<div align="center">

# Dante Live

**Um estúdio de produção audiovisual com experiência nativa de Mac.**

Cenas, captura, áudio e transmissão ao vivo — com interface própria em Swift e o motor audiovisual do OBS Studio.

<!-- current-download:start -->
[![Baixar Dante Live para Mac](https://img.shields.io/badge/BAIXAR_PARA_MAC-v0.1.8-18B7C7?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/dantetesta/dante-live/releases/download/v0.1.8/Dante-Live-0.1.8-macOS-universal.dmg)

**macOS 14+ · Apple Silicon e Intel · Universal 2**
Versão experimental **0.1.8**. Assinado com Developer ID e notarizado pela Apple. [Notas e fontes](https://github.com/dantetesta/dante-live/releases/tag/v0.1.8).
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

A versão **0.1.9** amplia a base funcional, em estágio experimental, com funcionalidades reais:

- Distribuição oficial assinada com Developer ID e notarizada pela Apple a partir da 0.1.8.
- Atualizações pelo menu do Mac, aviso ao abrir, changelog e instalação/reinício com proteção durante a live.
- Biblioteca visual de lives do YouTube com capa, título, visibilidade e horário local; seleção pelo botão Transmitir antes da confirmação.
- Adição de fontes em cartões ilustrados, com descrições simples, busca, categorias e opção separada para reutilizar uma fonte existente.
- Cenas e fontes com criação, duplicação, renomeação, ordenação por arrasto, visibilidade e bloqueio.
- Propriedades de fontes aplicadas automaticamente: seleções imediatas e campos digitados com pausa de 300 ms.
- Menu de contexto com propriedades em modal, filtros, renomear, ocultar, bloquear, transformar, ordenar e remover.
- Preview, seleção de elementos, arrasto, redimensionamento proporcional, crop, rotação, ajuste ao canvas e centralização.
- Integração de tela, janela, câmera, microfone, mídia, imagem, cor e texto por módulos selecionados da libobs; a validação varia por fonte e dispositivo.
- Painel de câmera com dispositivos, presets, formato/FPS e prévia da fonte.
- Mixer vertical estéreo com escala em dB, nível médio, pico e retenção de pico; volume, mute e filtros reais.
- ⌘F para ajustar ao canvas, Option/Alt nas alças para recortar e dentro da fonte para reenquadrar.
- Máscaras de câmera com formatos, cantos arredondados, zoom e enquadramento.
- Preferências de aparência: automática pelo Mac, clara ou escura.
- Convites temporários para até dois convidados no navegador, com câmera, microfone, tela e retorno de áudio sem a própria voz.
- Modo estúdio, corte/fade e transmissão manual RTMP/RTMPS, com início pelo estúdio e contagem regressiva cancelável.
- Configurações em abas, autosave, presets automáticos e criação contextual de presets personalizados.
- Diagnóstico de internet legível, canais RTMP nomeados e painéis laterais recolhíveis.
- Integração YouTube com OAuth, rascunhos de título/descrição/capa, agendamento e escolha do mesmo vídeo para transmitir (exige configuração Google; validação real pendente).
- Alerta visual de microfone sem sinal por 30 segundos durante a live, com recuperação automática e controle por fonte.
- Presets de **1080p, 1440p/QHD e 2160p/4K**, com 30/60 FPS e configuração de bitrate orientada pelo upload.
- Projeto JSON com salvamento atômico, cópia anterior e recuperação; conexão RTMP persistente, chave opcional no Keychain.

O produto é focado em lives: gravação de arquivos e replay buffer foram retirados da aplicação. A captura de tela continua disponível como fonte para transmissão.

O envio ao YouTube pela conexão manual foi testado pelo mantenedor. A integração OAuth/API da versão 0.1.6 foi validada com testes offline: login e agendamento reais ainda precisam ser conferidos em uma conta autorizada. Veja [como configurar o YouTube](docs/YOUTUBE.md).

**Há limitações conhecidas:** há relato de lag no preview/modo estúdio; o editor avançado e a cobertura de dispositivos estão incompletos. Consulte o [estado detalhado](docs/STATUS.md).

## Para onde queremos levar o projeto

### Produção mais simples

Evoluir grupos, seleção múltipla, alinhamento e atalhos. Painéis recolhíveis, ordenação por arrasto, propriedades em modal e canais nomeados já estão implementados; precisamos ampliar a validação de uso.

### Convidados por link

Disponível de forma **experimental na 0.1.9**: clique no ícone de convidar, gere um link e envie à pessoa. Ela informa o nome, autoriza câmera/microfone e pode compartilhar uma tela. O apresentador insere câmera, microfone e tela como fontes independentes, com mute, volume e visibilidade.

A mídia usa WebRTC; o link HTTPS usa uma ponte temporária Cloudflare Quick Tunnel, sem garantia de disponibilidade. A conexão direta usa STUN. TURN aceita credenciais temporárias opcionais e **não vem provisionado**: redes restritas podem não conectar. Não há limite de duração imposto pelo Dante, mas não prometemos sessões sem quedas. [Guia de convidados e limites](docs/GUESTS.md).

### Desempenho demonstrável

Medir CPU, GPU, memória, tempo por quadro, perdas e sincronização; reduzir cópias e trabalho redundante quando houver evidência de benefício. Não tratamos a troca de linguagem como ganho automático, nem redução de qualidade como otimização equivalente.

### Cobertura audiovisual

Avançar na equivalência funcional com os recursos macOS do OBS, incluindo editor, filtros, saídas, browser, câmera virtual e integrações auditadas individualmente. A prioridade atual é a transmissão pelo YouTube, com RTMP manual e integração de agendamento por API. Outras redes e transmissão simultânea ficam para etapas posteriores.

## Como colaborar

Procuramos contribuições em **Swift/SwiftUI/AppKit, C/C++/Objective-C++, Metal, áudio, vídeo, WebRTC, testes, acessibilidade e documentação**. Também precisamos de quem teste em Macs Intel e Apple Silicon, com diferentes câmeras, microfones e capturadoras.

Uma contribuição útil pode ser pequena: reproduzir um bug, tornar uma mensagem compreensível, corrigir um controle por teclado ou medir um cenário de produção. Abra uma [issue](https://github.com/dantetesta/dante-live/issues) com o problema e o comportamento esperado; para código, siga o [guia de contribuição](CONTRIBUTING.md) e envie um pull request.

## Compilar

O build requer um Mac, ferramentas Apple, Python 3, Git, Go (toolchain 1.27.2 para o helper de convidados) e o runtime oficial **OBS Studio 32.2.2**. Ainda há dependência de binários OBS pré-compilados; não é uma reconstrução integral de todas as bibliotecas a partir das fontes.

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
| `updates` | Catálogo assinado e histórico de changelogs; DMGs nas Releases |

Mais detalhes em [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Estado de distribuição

O botão no topo baixa o **DMG experimental corrente**. Abra o DMG, arraste Dante Live para Aplicativos e execute-o quando os dispositivos estiverem disponíveis. A distribuição oficial 0.1.8+ usa Developer ID e notarização Apple. Confira a origem oficial; não desative as proteções do macOS.

As [Releases](https://github.com/dantetesta/dante-live/releases) incluem o instalador, fontes correspondentes com dependências fixadas e SHA-256. A partir da 0.1.8, o aplicativo e o DMG oficiais são **assinados com Developer ID e notarizados pela Apple**. Builds locais sem credenciais continuam ad hoc. Testes prolongados e compatibilidade física Intel/macOS 14 permanecem pendentes. Os builds não substituem o OBS instalado.

A partir da 0.1.7, use **Dante Live → Verificar atualizações…** para as próximas versões. O aplicativo avisa ao abrir, mostra as novidades e instala após sua confirmação, preservando o projeto. Quem usa 0.1.6 ou anterior precisa instalar a versão corrente uma vez pelo DMG. [Como funcionam as atualizações](docs/UPDATES.md).

Para mantenedores: `scripts/release.sh` compila, testa, empacota e publica uma versão experimental com fontes e checksums; o botão é atualizado para a versão publicada. Veja [RELEASING.md](docs/RELEASING.md).

## Licença e créditos

Dante Live é disponibilizado sob a **GNU General Public License, versão 2 ou posterior**. Consulte [LICENSE](LICENSE) e [DEPENDENCIES.md](docs/DEPENDENCIES.md).

O projeto utiliza o trabalho do [OBS Project e seus colaboradores](https://github.com/obsproject/obs-studio), além das bibliotecas de terceiros identificadas no inventário. A referência atual é **OBS Studio 32.2.2**, commit `ba2f32bdf791005443988a4955e963663e16b1ed`.

Dante Live é um projeto independente; não é uma versão oficial nem possui afiliação anunciada com o OBS Project. A interface e a identidade visual são próprias.

Forks não recebem nossas credenciais. Para notarizar e distribuir uma versão própria, cada mantenedor usa sua conta Apple, identidade e chaves de atualização. Veja [assinatura, notarização e forks](docs/NOTARIZATION.md).
