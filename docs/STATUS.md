## Versão 0.1.25 — build e testes locais aprovados

Corrigido o acesso fora dos limites no último ponto da amostra da miniatura de onda do visualizador de áudio. O relatório de falha da 0.1.24 aponta para `VisualizerStyleThumbnail` na thread principal. O teste de regressão renderiza os dez estilos em uma janela SwiftUI de teste. O editor agora usa redimensionamento de conteúdo também para o componente de likes, preservando a altura ao arrastar a alça lateral. O painel permite ocultar qualquer comentário da fila e arquivá-lo imediatamente, com indicação distinta quando não foi ao ar; retirar apenas o olho da fonte mantém a espera de 30 segundos. O componente de likes tem seis modelos editáveis e consulta `channels.list` para o total arredondado de inscritos, além de contar os novos inscritos públicos que a API entregar durante a live. Build Universal 2 assinado com Developer ID e testes locais do app e chat aprovados. Notarização, DMG e publicação são as próximas verificações; transmissão pública, hardware Intel físico e conta YouTube real não foram validados nesta versão.

## Versão 0.1.24 — publicada e notarizada

Build Universal 2 para macOS 14+ assinado com Developer ID. Aplicativo e DMG receberam `Apple Accepted`, tickets anexados e aprovação do Gatekeeper. A suíte do app, os testes de captura, chat e gráficos e três convidados sintéticos no mesmo Mac passaram. A imagem montada teve 1.324 entradas do app idênticas à pasta de distribuição, incluindo hashes de arquivos e alvos de links. DMG e fontes correspondentes foram baixados anonimamente do GitHub e seus SHA-256 coincidiram com os arquivos locais; o catálogo público do atualizador contém a 0.1.24 e sua assinatura. [Release](https://github.com/dantetesta/dante-live/releases/tag/v0.1.24).

A página estática de uma VPS instalada antes desta versão ainda precisa ser atualizada para mostrar o botão de mudança de nome; o aplicativo publicado não altera arquivos da VPS automaticamente. Testes com convidados reais em redes distintas, Intel físico, macOS 14 em hardware dedicado e live prolongada seguem pendentes.

## Versão 0.1.24 — nome dinâmico do convidado

Ao inserir um convidado, o Dante cria uma camada própria para o nome. Ela começa junto à webcam, pode ser movida, redimensionada e ocultada sem alterar a câmera e tem seis estilos, fontes instaladas no Mac, tamanho e cores. O convidado conectado altera o nome na página do convite; uma chamada autenticada de controle atualiza a mesma fonte, sem recarregar a página ou renegociar o WebRTC. A camada acompanha a mudança de cena e é removida com o convite. Teste nativo confirmou pixels, seis estilos, troca de texto e persistência; três Chrome sintéticos no mesmo Mac confirmaram o mesmo peer e as mesmas trilhas após a troca. Não houve teste de convidado real em redes externas nem transmissão pública. VPS já instalada precisa receber os arquivos atualizados de `Sources/GuestWeb` para exibir o botão de alterar nome; o protocolo `/status` já é compatível.

## Versão 0.1.24 — cena dos convidados

A cena `05 · Cena dos convidados` usa o monitor 2 no centro, o microfone de lapela compartilhado e três espaços quadrados arredondados à direita. Cada convidado recebe câmera, microfone, nome dinâmico e uma tela separada que pode ser exibida pelo controle de visibilidade. As três telas são posicionadas na mesma área central. O motor agora reserva as trilhas internas 5, 6 e 4 para retornos individuais de até três convidados. Três navegadores sintéticos conectaram simultaneamente no mesmo Mac: seis fontes de vídeo, três medidores de microfone, retorno de programa para todos e exclusão da própria voz em cada retorno passaram. Redes externas, dispositivos físicos e transmissão longa permanecem sem validação.

## Versão 0.1.24 — alerta de silêncio após desconexão

O monitor agora continua acompanhando um microfone habilitado no mixer quando a fonte ainda está visível na cena em programa, mesmo que o dispositivo desligado passe a informar `sourceActive=false`. Antes esse estado removia a fonte da observação e zerava o tempo de silêncio. O aviso continua restrito a uma live em andamento e aparece como banner na interface após 30 segundos sem sinal. Testes locais passaram com estado de desconexão simulado e limiar temporal; desligamento de lapela real ainda pendente.

## Versão 0.1.24 — perfis de produção

Cada perfil mantém seu próprio projeto de cenas e fontes. O projeto legado `studio.json` permanece no lugar como perfil inicial; novos perfis têm arquivos separados e o catálogo salva qual foi aberto por último. Há seleção rápida no topo do estúdio e uma janela para criar, carregar e renomear. A troca salva o projeto atual e é bloqueada durante live, preparação ou sala de convidados. Configurações de transmissão e contas continuam globais. Testes de persistência e troca no motor passaram no build Universal 2 da versão.

## Versão 0.1.24 — MCP para cenas

Uma ponte MCP nativa por stdio, compatível com a revisão 2025-11-25, expõe ferramentas de leitura do canvas/cenas/fontes e edições restritas de cenas e elementos visuais. O app usa um socket Unix privado 0600 dentro de uma pasta 0700 do usuário; a opção fica desligada por padrão nas Preferências. As chamadas do motor são serializadas na thread principal. Transmissão, convidados, configurações sensíveis e comandos arbitrários não são expostos; edições são recusadas enquanto há saída ou preparação ativa. [Uso e limites](AGENT-MCP.md). Suíte local e teste de protocolo passaram; ponte incluída no build Universal 2 desta versão.

## Próxima versão — ajuste solicitado na preparação da live

- Reorganizar o seletor de modo de transmissão em **Preparar live**. Na interface atual, o rótulo “Modo de transmissão” e as opções “RTMP / RTMPS” e “Conta YouTube” ficam apertados lado a lado. Dar espaço e hierarquia visual claros, inclusive em janelas menores, sem alterar o comportamento dos dois fluxos. Validar visualmente em modo claro e escuro antes da distribuição.

## Versão 0.1.24 — estado do servidor de convidados

Após salvar ou importar a configuração, a guia Servidor TURN mostra um resumo sem campos de credenciais, com estado verde apenas depois que `/api/health` e `/api/turn` respondem corretamente. Testa ao abrir a guia, após salvar/importar e a cada 30 segundos enquanto ela está aberta. Falha, ponte reconectando e verificação antiga têm estados distintos; há botões para testar novamente e editar IP, porta ou token. Editar sem preencher outro token conserva o item no Acesso às Chaves. O teste de API não comprova mídia WebRTC entre redes reais. A suíte local `test-app.sh` e o typecheck x86_64/macOS 14 passaram; validação visual e em redes externas permanece pendente.

## Versão 0.1.24 — reforço de volume

O controle de volume do participante marca 100% como nível normal e reserva o trecho final do slider para reforço até 300%. O mixer alcança o mesmo teto em dB. Acima de 100%, o motor usa um filtro de ganho seguido por um limitador de pico antes do fader da fonte, mantendo a leitura unificada do volume e a configuração no projeto. Isso pode tornar fontes fracas audíveis; não corrige microfone ruim nem garante que a soma de todas as fontes ou o serviço de destino não distorça. Teste com fonte PCM sintética cobriu aumento medido no medidor, ordem ganho → limitador, ativação/remoção dos filtros e persistência após reabrir o projeto; transmissão real e escuta subjetiva ainda pendentes.

## Versão 0.1.24 — verificação de atualizações após a live

Convites que permaneceram abertos no app instalado após a transmissão podiam bloquear até a consulta por atualizações e gerar um aviso incorreto de live ativa. A consulta agora considera somente transmissão/preparação em andamento; uma sala de convidados aberta por outros motivos continua adiando a instalação e o reinício até ser encerrada. Regressão de estado com convite aberto e saída inativa passou em `test-app.sh`. A atualização instalada pelo Sparkle e a interface real ainda não foram exercitadas nesta alteração.

## Versão 0.1.24 — encerramento da sala e fontes instaladas

Ao confirmar o fim da transmissão, o Dante espera a saída ficar totalmente inativa e então fecha a sala: desconecta os peers, invalida os convites locais, desliga a ponte e remove as fontes temporárias dos convidados. O mesmo vale para um encerramento inesperado depois de a saída ter iniciado; a fase de reconexão ou parada ainda ocupada não fecha a sala antecipadamente. Testes sintéticos cobrem reconexão, parada e revogação dos convites; redes externas e uma live real ainda não foram exercitadas nessa mudança.

O seletor de fonte do chat e do destaque agora lista as famílias instaladas no Mac com busca, incluindo fontes adicionadas pelo usuário. A fonte escolhida permanece nas propriedades da fonte de cena. Caso o projeto seja aberto em outro Mac sem essa fonte, o desenho usa a fonte do sistema e a interface avisa. Catálogo, resolução e fallback passaram em testes; inspeção visual do controle fechado em tema escuro passou no harness local, e a janela de busca aberta ainda precisa de verificação visual.

## Versão 0.1.23 — publicada e notarizada

VPS própria de convidados por IPv4 HTTPS, gateway autenticado, Coturn com credenciais temporárias, guia Servidor TURN, importação de perfil protegido, preparação RTMP sem API e clareza dos limites de captura por aplicativo. Dois Chrome sintéticos no mesmo Mac conectaram pela VPS com relay TURN selecionado, mídia, mix-minus, reconexão e revogação. Renovação Certbot/webroot passou em dry-run. Aplicativo e DMG receberam `Apple Accepted`, ticket anexado e aprovação do Gatekeeper. O DMG Universal 2 passou em suíte local, leitura de volta com 1.147 entradas idênticas ao app e varredura de arquivos internos. Upload do DMG e fontes teve SHA-256 remoto igual ao local; download público e prompt retornaram HTTP 200. [Release](https://github.com/dantetesta/dante-live/releases/tag/v0.1.23) · [Prompt de instalação](../server/PROMPT-INSTALACAO.md).

O teste nativo da faixa falhou inicialmente no modo Accurate do OCR do macOS com `TextRecognition.CRImageReaderError`; o PNG renderizado estava correto. O teste passou ao ler o PNG no modo Fast, mantendo OCR de texto e leitura do QR no frame real. Convidados reais em redes externas distintas, live longa, primeira renovação real, Intel físico e macOS 14 físico ainda precisam de confirmação. Não há garantia de zero quedas ou de capacidade para mais de dois convidados.

## Alterações locais após 0.1.22 — preparação RTMP e clareza da captura

A guia Preparar live voltou a abrir sem conta YouTube quando o modo RTMP está selecionado. Título, descrição e capa são salvos localmente e título/capa aparecem na confirmação; o envio manual usa servidor/chave já configurados, com a mesma contagem regressiva. A seleção Conta YouTube mantém o fluxo OAuth/API. RTMP não publica metadados nem agenda no serviço remoto: o usuário deve configurá-los no YouTube Studio. Ainda sem build de distribuição ou transmissão real desta alteração.

As propriedades de áudio do Mac agora informam que a seleção por aplicativo inclui todas as abas do navegador; a captura de janela isola sua imagem, não o áudio por aba. Isolamento de aba com áudio exigiria integração autorizada com o navegador, ainda não implementada. Typecheck arm64/x86_64 e suíte local `test-app.sh` passaram com runtime isolado da versão 0.1.22, sem saída de rede ou dispositivos físicos nesta alteração. Typecheck Intel não substitui teste em hardware Intel.

## Versão 0.1.22 — recuperação do convidado, captura e enquadramento

O convidado tenta reconstruir automaticamente a conexão WebRTC após falha de mídia ou negociação obsoleta, mantendo convite, identificação e trilhas autorizadas. Oscilações breves aguardam cinco segundos; tentativas seguintes usam espera crescente até 15 segundos. O botão Reconectar agora permite agir sem aguardar. Revogação e saída encerram as tentativas. O Quick Tunnel continua temporário: se a sala ou o endereço mudar, é necessário enviar novo convite. Esta mudança não substitui TURN, não garante conexão em toda rede e não comprova sessão de longa duração.

A opção de captura de monitor passa a se chamar “Ocultar Dante Live da captura”. O módulo mac-capture é recompilado a partir do source fixado, com patch que impede o callback do formulário de consumir antecipadamente a mudança de `hide_obs`. O filtro continua usando o bundle ID do aplicativo em execução; a chave persistida foi preservada. Teste com callbacks reais reproduz a falha no source original e passa com o patch, incluindo ligar, desligar, leitura do formulário e restauração. Binário Universal 2 compilado; exclusão visual de uma captura real ainda não validada nesta alteração.

Option/Alt mostra borda e oito alças laranja. “Ajustar enquadramento” mantém o modo sem teclado, permite recortar pelas alças e mover o conteúdo dentro da caixa, com centralização e Esc para concluir. A guia translúcida da parte cortada é uma camada somente do editor, reutiliza a fonte e não entra no programa. Selecionar outra fonte encerra o modo. Aplicável a fontes visuais com transformação livre, incluindo imagem, vídeo e câmera; filtros que já cortam pixels da própria fonte continuam limitando o conteúdo disponível.

Typecheck macOS14 arm64/x86_64, geometria rotacionada/espelhada e gestos nativos aprovados: recorte vertical, enquadramento sem Alt mantendo a caixa, um undo por arrasto e saída ao trocar seleção. QA visual isolado com pixels reais da fonte sintética confirma guia translúcida fora do recorte, conteúdo interno inalterado e remoção da guia ao concluir; screenshots em `build/framing-qa`. Não incluído no DMG 0.1.21; instalação no Mac do operador não efetuada automaticamente.

## Versão 0.1.21 — painéis e histórico do chat

Painéis SwiftUI convertidos para NSPanel independentes, móveis pela barra de título, coexistentes e sem sessão modal. Dismiss/bindings/onDismiss mantidos, reabertura e encerramento antes da engine cobertos. Chat com três abas, busca nome/texto, ordenação cronológica e tags coloridas. A classificação só observa destaque ativo no programa enquanto streaming; saída do ar agenda arquivamento após30s, reexibição cancela o prazo. Histórico limitado a500 itens, moderação/reset limpam estado. Feed automático preservado.

Testes locais: dois painéis reais coexistentes, movimento, fechamento independente, reabertura; relógio determinístico para30s, filtros/ordem/reset; teste libobs confirma sourceActive acompanha programa/Cut e ignora alterações somente na prévia. Capturas claro/escuro em build/chat-qa/panel-*.png. Logs panels-history-tests.log e program-history-tests.log. Incluído na versão 0.1.21. Sem live pública ou manipulação de aplicativos instalados.

## Versão 0.1.20 — chat responsivo e alertas

Biblioteca em duas abas, ações Transmitir/Editar por cartão e remoção de preparações locais com confirmação. Agendamentos saem da lista local e podem ser restaurados; nenhuma exclusão remota. Exclusão persistente inclusive da última preparação, isolamento por conta e rollback em erro de disco. Atalho nas configurações fecha as folhas antes de abrir a confirmação existente.

Cartões por mensagem com seis estilos principais e seis variações; nome/texto/espaçamento separados, iniciais e cores por autor, opacidade e destaque Super Chat com o mesmo desenho. Dimensões de fonte editáveis pelas alças, reflow sem escala não uniforme. Paginação de destaque adaptada ao espaço. Exemplos somente na camada SwiftUI do editor, estruturalmente fora da textura do programa; ocultos durante preparação/contagem/saída ativa.

Fonte de alertas: total de likes (15 s), inscrições públicas recentes (30 s), fila de cinco segundos, referência inicial sem replay e IDs únicos por sessão. Sem identificação de quem curtiu, sem inscritos privados ou garantia de tempo real. Consultas somente quando habilitado, limites de fila/memória, tratamento de quota e reset. [Operação e limites](YOUTUBE-OVERLAYS.md). Testes locais de transporte, filas, rasterização, geometria e programa nativo aprovados. Incluído na versão 0.1.20; conta real/inscrições reais e Intel físico não testados.

## Versão 0.1.19 — faixa rolante e QR Code

Novas fontes nativas para faixa de texto no rodapé (altura, velocidade, cores, fonte, negrito/itálico) e QR Code (link, texto ou Pix estático, três estilos, cores e logo). Gerador local Core Image, confirmação de leitura Vision antes de aplicar. Pix valida formato/CRC e dígitos de CPF/CNPJ; não verifica cadastro bancário ou titularidade. [Uso, referências e limites](SCENE-GRAPHICS.md).

Testes com o vetor oficial BCB, 18 combinações de QR, quadros reais de programa, persistência e isolamento de estúdio; nenhum pagamento real executado.

## Versão 0.1.18 — chat e Super Chats (experimental)

Duas fontes nativas: janela de chat (últimas quatro mensagens comuns) e destaque animado, com 12 estilos, cores de destaque/fundo/texto, seis famílias de fonte e tamanho. Painel Chat na barra superior separa conversa e fila de Super Chats/Super Stickers; aprovar, ocultar, marcar como exibido e navegar páginas. Mensagens pagas não entram no feed automático; texto completo no painel e no destaque paginado. Super Stickers usam descrição textual porque a API não fornece sua imagem. No modo estúdio, o conteúdo é uma entrada ao vivo compartilhada; posição/visibilidade da cena continuam sujeitas a Corte/Transição.

Conexão usa OAuth do evento realmente iniciado, `snippet.liveChatId` e `liveChatMessages.list`, respeitando `pollingIntervalMillis` com mínimo de cinco segundos. Reconexão com backoff, cursor e geração de sessão; quotas/permissões/encerramento aparecem no painel. Ainda não usa `streamList`: polling consome quota (5 unidades por chamada) e não oferece chegada instantânea. Nenhuma publicação, exclusão ou moderação remota é executada.

Memória limitada a 100 mensagens comuns, 500 apoios pendentes e 10.000 IDs recentes. Fila cheia avisa; não descarta silenciosamente apoios antigos para receber novos. Mensagens, fila e texturas limpas ao parar/encerrar; apenas fontes/estilos/transforms são salvos. Textos remotos são desenhados como texto simples, sem HTML ou carregamento de avatares. Validação local: transporte falso, moderação/dedup/paginação/reset, capturas claro/escuro, e pixels reais de saída do libobs em processo isolado. YouTube real, doações reais e sessões prolongadas ainda não validados. Incluído na versão 0.1.18; validação com conta real permanece pendente.

Referências: [mensagens e Super Chats](https://developers.google.com/youtube/data/live/reference/rest/v3/liveChatMessages), [consulta e cadência](https://developers.google.com/youtube/data/live/reference/rest/v3/liveChatMessages/list).

## Versão 0.1.18 — organização da preparação de lives

Formulário reorganizado em Conteúdo e Público e interação, com título maior, descrição com orientação, categoria/palavras-chave recolhíveis, cartões de visibilidade e capa clicável em coluna menor. Ações Salvar para transmitir/Agendar e status de autosave ficam fora da rolagem. Layout passa para uma coluna abaixo de 760 pontos; janela de configurações usa até 1000×820 pontos, limitada à área útil da tela. Tema claro/escuro acompanha o app. Fluxos de persistência e publicação continuam nos mesmos métodos do modelo. Incluído na versão 0.1.18.

Limite do canvas: fundo externo cinza-azulado opaco, adaptado ao tema, e borda fina no retângulo exato de saída, tanto na prévia quanto no programa. Decoração apenas da UI, sem mudar enquadramento, coordenadas das alças ou textura enviada pelo motor. Incluído na versão 0.1.18.

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
| YouTube | RTMP manual com preparação local de título/descrição/capa (sem publicação desses dados) e integração OAuth/API para metadados, capa, agendamento e seleção de vídeos; API validada offline, autenticação/produção reais pendentes |
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

## Correção local — salvar preparação sem abrir a biblioteca

O botão de preparação foi simplificado para **Salvar**. Após `saveDraftForLater()` confirmar persistência, habilita o modo YouTube e fecha as configurações, retornando ao estúdio. Falha de validação/persistência mantém o formulário aberto com a mensagem existente. Não abre a biblioteca nem inicia transmissão. O botão **Transmitir** do estúdio mantém seleção, confirmação e contagem regressiva. Alteração local, ainda não distribuída; sem teste em live pública.
## VPS de convidados por IPv4 — validação em curso

O servidor dedicado Ubuntu 24.04 foi configurado com HTTPS por IP, Coturn, renovação automática, firewall e gateway Python de convites. O app agora tem guia Servidor TURN, guarda token no Acesso às Chaves, aceita importação de perfil e prepara convites no endereço da VPS. Compilação universal e suíte local passaram. Dois navegadores Chrome sintéticos neste Mac atravessaram o HTTPS da VPS e completaram mídia WebRTC, retorno sem a própria voz, reconexão e revogação; um segundo teste forçou e confirmou candidato TURN relay para ambos. A simulação de renovação do certificado com Certbot/webroot passou; a primeira renovação real ainda não ocorreu. Convidados reais em redes externas distintas e duração prolongada continuam pendentes. Não há garantia de zero quedas ou de capacidade para mais de dois convidados. O executável frpc detectado/removido pelo macOS foi retirado do projeto e do VPS; o gateway usa código Python/Swift próprio.
## Versão 0.1.24 — visualizador de áudio na cena

Fonte de vídeo nativa e transparente vinculada por UUID a uma fonte de áudio do projeto. O PCM capturado por callback alimenta onda e análise FFT de 48 bandas, com dez desenhos, duas cores e sensibilidade. O componente não injeta nem modifica som; redimensionar pelas alças recalcula o desenho na resolução escolhida. Fontes silenciosas ficam em repouso. O vínculo e o estilo são salvos no projeto. Teste nativo com WAV sintético confirmou pixels reativos nos dez estilos, mute/repouso, redimensionamento e restauração. Build Universal 2 com Developer ID passou. Não há validação em live real.
