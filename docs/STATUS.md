## Versão 0.1.17 — áudio e latência

Implementados em código: redução de ruído opcional por participante (RNNoise/Speex, bypass persistindo ajustes), bitrates/FPS separados para convidados, preferência H.264, recepção de vídeo sem fila assíncrona adicional, saída VT sem B-frames e x264 zerolatency. Novas preparações YouTube usam ultrabaixa latência; configurações salvas são preservadas, 4K exige Normal. Estúdio oferece link do vídeo iniciado para copiar.

Cancelamento de eco acústico NÃO está resolvido: mix-minus direto passou; o ensaio de AEC para voz recaptada falhou e a tentativa não foi mantida no produto. [Pesquisa, decisões e limites](MEDIA-RESEARCH.md).

## Versão 0.1.16 — preparação de lives e biblioteca local

Guia Preparar live separada de Conta YouTube: formulário de título/descrição/visibilidade, capa com prévia, categoria/palavras-chave/latência e opções Salvar na lista ou Agendar. Agendamento abre calendário nativo do Mac com horário, fuso, canal e visibilidade; cria o vídeo no YouTube sem iniciar transmissão. Transmitir reúne várias preparações locais e eventos remotos, depois confirma e mantém contagem 3–2–1.

Biblioteca por canal com IDs próprios, autosave, migração do rascunho legado (inclusive quando coexistia com uma seleção remota), cache dos eventos e journals individuais para retomar criação parcial sem repetir inserts. Dados confirmados são verificados novamente antes de iniciar. Falha de disco impede trocar/descartar a preparação atual. Lives remotas continuam editáveis no YouTube Studio.

Validação com transporte offline: migração, múltiplas preparações/capas independentes, persistência/reabertura, canais isolados, falha de disco, snapshot da confirmação e criação/agendamento com retry. A contagem regressiva existente mantém teste de cancelamento e início único. Nenhuma live foi criada/transmitida em conta real para esta validação; calendário e formulário usam controles reais em fixture local isolada. Demais limites de plataforma/rede continuam abaixo.

## Versão 0.1.15 — nova compilação de distribuição

Nova compilação da base 0.1.14, com versão/build próprios para distribuição e atualização. Não adiciona funcionalidades nem altera o comportamento do aplicativo. Permanecem os recursos e limites de validação descritos abaixo.

## Versão 0.1.14 — participantes, retorno e estúdio

Painel Participantes abaixo de Cenas: câmera, tela e microfone agrupados, nome de entrada, cor estável por participante, escolha/mudança da cena, visibilidade, mute, volume e escuta local. Componentes da sala saem da lista comum de fontes; a ordem das demais camadas preserva seus lugares. Revogar/encerrar a sala remove seus itens da composição. Fontes órfãs de versões antigas continuam acessíveis para remoção manual.

Retorno direto do programa por WebRTC, até 960×540 e 15 FPS, independente da qualidade da transmissão principal. O convidado pode silenciar somente sua escuta. Câmera/microfone usam verde/vermelho; tela usa verde/neutro. Receivers são associados também ao aplicar a descrição remota, cobrindo tracks disponibilizadas antes do callback de recepção. Compartilhamento iniciado após conexão e parado/reiniciado foi testado.

Modo estúdio publica uma composição privada: edição de texto, posição, crop e visibilidade na prévia só chegam ao programa após Corte/Transição. Dispositivos e tracks continuam compartilhados: troca de câmera/microfone, filtros de uma captura e mixer continuam operações globais em tempo real. O programa local reutiliza a textura já composta em vez de desenhar novamente todas as fontes. Teste sintético 2560×1440/30 FPS, dois displays, cinco segundos por modo: em estúdio, 450 → 300 chamadas de desenho da fonte para 150 quadros; zero quadros perdidos em ambas as execuções. Isso mede redução de trabalho, não prova ausência de lag com hardware/rede reais.

Option + arrasto usa coordenadas fixas do canvas para recorte e movimento. Testes cobrem recorte superior/inferior, enquadramento vertical, geometria espelhada/rotacionada e publicação do crop. Máscaras em grade compacta adaptativa. Reuso exclui a própria cena e ancestrais que formariam ciclo; motor também rejeita esses casos. Encerramento tem confirmação específica.

Permissões de captura são consultadas/solicitadas pela API apropriada; ScreenCaptureKit verifica o acesso pelo próprio serviço. Recusa oferece o painel correto e instruções de recuperação. Notarização não concede acesso automático; não alteramos o banco TCC nem reiniciamos o app durante live.

Validação: suíte Swift/Python, testes nativos de isolamento e dois Chrome com mídia sintética/WebRTC real (medidores, tela tardia, retorno em pixels, mix-minus, controles, organização e revogação). O problema de áudio/tela com o dispositivo remoto do usuário não foi reproduzido com os dispositivos sintéticos; depende de reteste no cenário real. Safari/Firefox, Intel físico, macOS 14 real e sessões prolongadas permanecem pendentes.

## Versão 0.1.13 — conexão direta de convidados

Negociação WebRTC incremental (trickle ICE): o navegador e o Mac enviam SDP sem aguardar todos os candidatos de rede. Candidatos tardios são trocados por HTTPS autenticado, vinculados à tentativa de conexão e limitados em quantidade/tamanho. Elimina o cancelamento obrigatório após 15 segundos de descoberta de rede, que podia descartar um caminho direto já disponível. Mensagens não presumem necessidade de TURN nem culpam antivírus.

Dois Chrome isolados com mídia sintética passaram em loopback e pelo Quick Tunnel público, sem TURN e com STUN configurado para um endereço inacessível. No teste público, a propriedade de descoberta do navegador foi mantida em gathering: conexão não esperou sua conclusão. Quatro fontes de vídeo, dois microfones, retorno mix-minus, revogação e rejeição de candidatos de tentativa anterior passaram. Teste público ocorreu no mesmo Mac; não comprova redes externas/NAT distintas ou o cenário do convidado do usuário.

Quick Tunnel continua apenas como página/sinalização, não relay de mídia. A correção não garante conexão direta quando as redes bloqueiam todos os caminhos. Não foi implantado TURN ou outro retransmissor, nem alterado firewall/antivírus. macOS permitia entrada para /Applications/Dante Live.app no diagnóstico de leitura.

## Versão 0.1.12 — dispositivos do convidado e orientação de câmera

Corrige a primeira ativação do convidado: o placeholder não é mais enviado como deviceId. Seletores listam dispositivos válidos, a permissão negada permite nova tentativa e falha do medidor não bloqueia câmera/microfone. Prévia e controles reorganizados. Máscaras de câmera com opções horizontais e verticais para oval, retângulo e retângulo arredondado.

Regressão reproduzida na página anterior. Chrome isolado passou com mídia sintética e com getUserMedia nativo usando dispositivos de teste do navegador: quadros de vídeo, nível de áudio, enumeração, recusa e recuperação. Layout em sete viewports. Máscaras verificadas em GPU e persistência; typecheck arm64/x86_64 macOS14. Câmeras/microfones físicos e Safari/Firefox não foram testados neste incremento.

## Versão 0.1.11 — manual YouTube e organização local

Inclui guia HTML offline revisado com o tutorial do autor, vídeo e links por etapa; recurso exigido no pacote. A biblioteca permite ocultar/restaurar lives somente neste Mac, por canal, sem chamadas de alteração à API. README com novas capturas reais em modo escuro e preferências. Claro, Escuro e Automático continuam disponíveis.

Contratos offline de ocultação/persistência/reversão passaram; compilação arm64 e typecheck x86_64/macOS 14 passaram antes da preparação da release. Build Universal 2, suíte e assinatura/notarização são verificados novamente pelo pipeline de publicação. Intel físico, macOS 14 real e testes prolongados continuam pendentes.

# Estado do projeto

Release experimental: **0.1.17 (18)**. Foco exclusivo em produção de lives para Mac: configurações persistentes em abas, presets automáticos e personalizados, início pelo estúdio com contagem regressiva e alerta de microfone sem sinal. Gravação de arquivos e replay buffer foram retirados da aplicação por decisão de produto. Convidados por link foram implementados experimentalmente; TURN e testes em redes distintas continuam pendentes.

| Área | Estado atual |
|---|---|
| Interface | SwiftUI/AppKit, português, painéis redimensionáveis e recolhíveis, modo estúdio |
| Cenas e fontes | Criar, duplicar, renomear, ordenar por arrasto, visibilidade, bloqueio e reuso |
| Editor | Seleção única, arrasto, resize proporcional, campos de transformação, crop, ajuste e centralização |
| Captura | Integração de módulos de tela, câmera e áudio; cobertura de dispositivos ainda parcial |
| Mixer | Volume, mute, medidores, filtros e parâmetros de sincronização |
| Produção | Corte/fade, RTMP/RTMPS manual e contagem regressiva cancelável |
| Presets | 1080p, 1440p e 2160p automáticos; presets personalizados com nome, resolução/FPS/encoder/bitrates |
| Projeto | Salvamento atômico, backup, recuperação e exportação/importação de JSON compatível |
| Conexões | Canais RTMP nomeados com servidor e chave independente no Keychain; seleção automática |
| Convidados por link | Até dois convidados, fontes separadas e retorno mix-minus; experimental, TURN não provisionado |
| YouTube | RTMP manual e integração OAuth/API para metadados, capa, agendamento e seleção de vídeos; API validada offline, autenticação/produção reais pendentes |
| Outros destinos simultâneos | Fora da prioridade atual; não implementado |
| Browser e câmera virtual | Pendentes; nenhum módulo Qt carregado |
| Editor avançado | Propriedades em modal e drag-and-drop de camadas disponíveis; grupos, seleção múltipla e guias completas pendentes |
| Distribuição | DMG experimental público, fontes e checksums; Developer ID e notarização obrigatórios na release 0.1.8+ |

## Validação disponível

As validações locais anteriores desta base em Apple Silicon incluíram 67 verificações do motor e 24 de posicionamento, sem falhas, com mídia sintética e RTMP loopback. Há testes de persistência, geometria, presets e ciclo de vida de previews. O mantenedor relatou um teste funcional de live no YouTube com câmera.

Essas evidências são limitadas ao cenário executado: os testes sintéticos de saída usaram 640×360/10 FPS. Não comprovam a operação de todos os presets, dispositivos ou fontes.

## O que ainda precisa de comprovação

- Execução em macOS 14 real e em Macs Intel físicos. Rosetta não substitui esse teste.
- Sessões contínuas de pelo menos duas horas e crescimento de memória.
- Benchmark comparável com OBS: mesma máquina, cena, resolução, FPS, encoder e qualidade.
- Reconexão de rede estabelecida, disco cheio, permissões negadas e desconexão física de dispositivos.
- HDR, sincronização audiovisual de capturas reais, VoiceOver e navegação completa por teclado.
- Instalação em máquina limpa e cadeia completa de fontes/licenças dos binários distribuídos.

A 0.1.14 reduz redesenho redundante do programa com medição sintética. A eliminação do lag relatado em câmera/rede reais ainda depende de reteste. Não anunciamos latência zero.

## Incremento 0.1.4

Propriedades da fonte passam a aplicar seleções e interruptores imediatamente. Campos digitados e cor são agrupados por uma pausa de 300 ms, preservando o vínculo com a fonte original. JSON avançado mantém confirmação explícita para validar o objeto completo. O painel dedicado da câmera também aplica as escolhas automaticamente e mantém as verificações de permissão/formato/FPS.

A lista usa drag-and-drop nativo com um token de sessão interno para aceitar somente elementos da mesma cena e rejeitar arrastos desatualizados. O motor recebe a ordem completa em uma operação, com rejeição de listas incompletas/duplicadas e uma etapa de desfazer/refazer. O menu de contexto acrescenta Propriedades, Filtros, Remover e controles de visibilidade/bloqueio/transformação/ordem. O ícone da entrada de áudio agora é de microfone.

Testes com fontes sintéticas verificam a ordem real no motor, seleção estável, histórico, persistência, rejeição de ordens inválidas e isolamento das edições por fonte. Trocas de câmeras, celulares e microfones físicos precisam de validação do usuário; não foram abertas capturas físicas durante este incremento.

A lista de fontes usa NSTableView/AppKit com seleção e menu nativos, sem recarregar linhas a cada atualização dos medidores. O teste do controlador cobre pasteboard/token, origem incorreta, destino inválido, drop aceito, mudança real no motor e seleção da fonte certa pelo menu. A aplicação automática foi observada na interface tanto no painel como no modal (dimensões atualizadas no motor e painel sincronizado ao fechar). O gesto completo de arrastar com mouse não foi confirmado pela automação; validação manual solicitada ao mantenedor, ainda sem resposta.

## Incremento 0.1.5

Configurações da live separadas em Qualidade, Vídeo e áudio, Conexão e Diagnóstico. Preferências são gravadas atomicamente em live-settings.json, na pasta de suporte do aplicativo; a chave é exclusiva do Keychain, opcionalmente apenas em memória. Campos digitados usam debounce de 300 ms e flush ao fechar; seleções aplicam imediatamente. Arquivo inválido é preservado e edição bloqueada com mensagem. Presets personalizados guardam somente vídeo/áudio, sem conexão ou segredo; edição posterior cria ajustes personalizados sem alterar o preset nomeado original. Nomes duplicados são recusados.

Durante transmissão ativa, edições são persistidas para a próxima live, sem reiniciar o vídeo. Fora da live, resolução/FPS válidos são aplicados automaticamente; falhas são exibidas. Presets de fábrica recalculam bitrate pelo upload; presets personalizados preservam o bitrate escolhido. Upload insuficiente mantém o mínimo do preset e exibe aviso, sem redução automática de resolução.

A janela serve apenas para configurar. Transmitir, no estúdio, valida a conexão e faz contagem 3–2–1 cancelável; a indicação Ao vivo depende do sinal de início do motor. Isso não confirma reprodução na página do YouTube. A aplicação rejeita comandos de gravação/replay e não oferece esses controles. O motor upstream ainda contém rotinas internas históricas de saída, que não são expostas pelo produto.

O alerta de áudio monitora fontes ativas não silenciadas, com volume maior que zero, roteadas para a trilha da live e sem modo somente monitoramento. Entradas de microfone Core Audio são monitoradas por padrão; fontes de câmera e outras entradas podem ser habilitadas no mixer. Usa timestamp monotônico do último pico de entrada acima de -90 dBFS, capturado sem alocação/IO no callback. Após 30 segundos sem sinal durante a live, mostra banner persistente somente na interface; volta ao normal quando recebe sinal. Silêncio de filtros/noise gate também pode gerar aviso: não é diagnóstico de bateria. A captura de toda a tela pelo operador pode incluir qualquer interface visível, inclusive este aviso; prefira janela/aplicativo específico quando necessário.

Testes automatizados cobrem autosave/reabertura, Keychain por interface isolada, ausência de chave no JSON, presets, alteração durante saída ativa, arquivos inválidos, aplicação real de vídeo, contagem cancelável e limiar/recuperação do alerta. O caminho real do callback foi exercitado com WAV sintético, incluindo sinal presente e idade crescente após parar a mídia. Sem transmissão pública, captura física ou medição real de upload nesta validação. Desconexão/bateria de microfone físico e início no YouTube exigem teste real pelo mantenedor.

A automação da interface não conseguiu obter a árvore de acessibilidade da nova cópia isolada (timeout), embora o processo permanecesse em execução. Revisão visual das novas abas e teste de uso solicitados ao mantenedor; não declarar essa validação como aprovada.

## Incremento 0.1.6

Diagnóstico de upload com linguagem simples, velocidade arredondada, avaliação dos ajustes atuais e sugestão Full HD/2K. Capacidade para 4K é informada separadamente. Não mede estabilidade, latência até o YouTube nem capacidade do computador. Criação contextual de preset com nome automático e renomeação; canais RTMP nomeados isolam as chaves mesmo quando compartilham o servidor. Cenas e Propriedades têm controles de recolher/restaurar persistidos. Abas usam seletor explícito, evitando o colapso observado no TabView.

Transmitir abre confirmação com destino, título, capa quando disponível e chave mascarada. No modo manual, metadados continuam sob controle do serviço. No modo YouTube, OAuth desktop/PKCE permite conectar canais, manter rascunhos locais, criar vídeo agendado, enviar metadados/capa, criar e vincular stream e transmitir no mesmo ID. Uma criação remota confirmada é registrada antes da próxima etapa; resposta perdida bloqueia nova criação automática. A data agendada não inicia o aplicativo ou a transmissão automaticamente. Lives já criadas são editadas no YouTube Studio.

Cliente OAuth próprio é necessário nesta versão: importar JSON desktop e autorizar pelo navegador. Tokens e configuração Google ficam no Keychain; JSON local contém somente preferências, IDs, metadados e referências de imagens. Nenhuma credencial Google do OBS é reutilizada. Consulte YOUTUBE.md. A UI distingue envio RTMP de confirmação de estado live pela API. Encerrar uma live iniciada pela integração também solicita encerramento no YouTube; falha exige conferir o Studio.

Compilação Universal 2 e testes Swift com libobs passaram. Novos testes cobrem canais, migração, diagnóstico, nomes de presets, callbacks OAuth e contratos HTTP. Agendamento, bind e retomada após falha foram testados com transporte offline; nenhuma conta foi autorizada e nenhuma live foi criada/transmitida no YouTube pelo agente. A automação CUA da cópia QA016 retornou timeout de acessibilidade, portanto os novos layouts/gestos ainda precisam de conferência visual do mantenedor.

## Incremento 0.1.7

Atualizador nativo Sparkle 2.10.0, menu Verificar atualizações junto de Sobre e consulta ao abrir. Catálogo e DMG exigem assinaturas Ed25519; changelog é exibido antes da instalação. Download e reinício dependem da decisão do operador. Transmissão, preparação, confirmação e contagem regressiva bloqueiam a instalação; um download pronto durante a live aguarda retomada explícita. O projeto deve ser salvo com sucesso antes de encerrar.

Catálogo em `updates/`, DMGs imutáveis em Releases e fontes correspondentes incluem Sparkle. A publicação verifica assets antes de enviar o catálogo. Instalação inicial da 0.1.7 é manual para quem tem versões anteriores. Assinatura ad hoc/notarização e demais pendências de hardware permanecem. Consulte UPDATES.md.

## Incremento 0.1.8

Distribuição oficial com Developer ID, Hardened Runtime e timestamp seguro em todo o código nativo. App e DMG recebem tickets de notarização; publicador exige validação do Gatekeeper e dos tickets antes de atualizar Releases e catálogo. Credenciais continuam exclusivamente no Keychain local. Forks podem compilar localmente ou usar credenciais próprias. A chave pública Ed25519 e o bundle ID do Dante foram preservados. Nenhum recurso de gravação foi reintroduzido.

0.1.8 publicada: Apple Accepted sem issues para app e DMG, tickets anexados e Gatekeeper Notarized Developer ID. 35 componentes Mach-O com mesma identidade e Hardened Runtime; read-back do DMG com 1.128 arquivos/symlinks idênticos ao bundle final. Suíte Swift/Python passou; previews/editor executaram com validação de bibliotecas ativa. Nenhuma chave privada ou credencial foi exportada. Certificados públicos e identidade são parte normal da assinatura distribuída.

## Incremento 0.1.9

Janela Adicionar à cena redesenhada com cartões de ícones, nomes curtos e descrições por tipo de conteúdo. Busca inclui o nome original do módulo; categorias distinguem câmera/tela, áudio, elementos e métodos legados de compatibilidade. O catálogo continua vindo exclusivamente dos módulos reais carregados. Selecionar um cartão mostra explicação, nome sugerido sem colisão e propriedades disponíveis em um painel independente. Usar existente tem sua própria lista e informa o compartilhamento entre cenas. Nenhum dispositivo é aberto apenas ao navegar pelo catálogo.

A mudança é de apresentação e preserva a ponte, permissões, criação/reuso e janela dedicada de câmera. Não adiciona navegador, convidados ou suporte novo a dispositivos.

Biblioteca de lives em janela própria: cartões com capa, título, visibilidade e data/hora no fuso local. No modo YouTube, Transmitir abre a lista do canal conectado; Continuar seleciona e persiste o vídeo, fecha a biblioteca e prepara a confirmação existente. Abrir a lista apenas consulta o canal. Rascunho local é separado dos vídeos já criados; sua criação continua dependente da confirmação. RTMP manual mantém o fluxo anterior, pois a chave não permite consultar o catálogo do YouTube. A aba YouTube oferece Ver minhas lives. Cancelar não inicia envio; instalação de atualização fica bloqueada durante a seleção.

## Incremento 0.1.9 — editor, áudio e convidados

Implementados: cartões de fontes e biblioteca visual YouTube, ⌘F, crop/pan com Option, máscaras GPU com enquadramento, aparência persistente e mixer estéreo vertical RMS/pico/hold. Convidados por token: até dois navegadores, câmera/tela/microfone separados, admissão, revogação e retorno mix-minus. Ver [GUESTS.md](GUESTS.md) para operação e limites.

Fontes: Sources/App/GuestModel.swift, GuestHTTPServer.swift, GuestsView.swift, Sources/Bridge/DanteGuestRTC.mm, Sources/GuestWeb. Dependências e hashes em packaging/guests-lock.json. LiveKitWebRTC BSD/patentes e empacotamento MIT; cloudflared Apache 2.0 e Go com licenças transitivas. Ambos Universal 2; helper recompilado com deployment target 14.0 porque o binário upstream exigia 15.0.

Aceitação: dois peers Chrome com mídia sintética real, fontes e medidores libobs, retorno espectral sem própria voz, revogação; segurança HTTP/token/origem; máscaras verificadas em pixels GPU. Não equivale a teste de redes NAT distintas, TURN, Safari, duas horas, Intel físico ou macOS 14 real. TURN não provisionado; Quick Tunnel temporário sem SLA. As pendências históricas de convidados passam a ser estes limites, não ausência total da funcionalidade.

## Incremento 0.1.10 — identidade e espaço de trabalho

Ícone oficial fornecido pelo mantenedor, com variantes 16–1024 px e transparência, usado também no cabeçalho. Galeria de capturas reais de um projeto sintético no README.

Divisória abaixo do canvas com alça de 12 pontos, ajuste por arrasto, proporção persistente, dois cliques para restaurar e alternativa por teclado/acessibilidade. O enquadramento da cena não muda: somente o espaço disponível para prévia, fontes e mixer.

CUA confirmou arrasto, setas, ação acessível, restauração por dois cliques, reabertura com a proporção salva e ampliação/redução da janela. Não houve nova validação em Intel físico, macOS 14 real ou transmissão pública neste incremento.

## Convite compacto e primeira ativação — alteração local de 2026-10-16

Correção de placeholder enviado como deviceId de câmera/microfone, com regressão reproduzida antes e aprovada depois. Página compacta na altura do desktop e adaptada ao celular, preparação explícita, mensagens de permissão e limpeza de streams. Sete viewports e fluxos locais passaram em Chrome com dispositivos sintéticos; detalhes em docs/GUESTS.md. Mudanças ainda não incluídas no app instalado ou em nova distribuição; OBS e salas em execução preservados.
