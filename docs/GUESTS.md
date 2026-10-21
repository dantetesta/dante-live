# Convidados por convite — experimental, 0.1.14

Na 0.1.24, a sala aceita três convidados. O retorno individual usa as trilhas internas 5, 6 e 4 para os convidados 1, 2 e 3, respectivamente, excluindo a voz de cada pessoa do próprio retorno. Fontes do apresentador devem participar das três trilhas. Na cena `05 · Cena dos convidados`, a câmera de cada pessoa é enquadrada como quadrado arredondado na coluna direita, sua tela entra oculta e ocupa a área central quando o operador liga o olho. O nome dinâmico ocupa a faixa sob cada câmera; o texto de reserva da cena também é editável. Três navegadores sintéticos passaram no mesmo Mac; isso não comprova estabilidade com convidados reais em redes diferentes.

## Como usar

1. No topo do estúdio, clique no ícone de convidar participantes e em Convidar.
2. Copie o link e envie apenas à pessoa convidada. São até três convidados simultâneos, além do apresentador.
3. No navegador, a pessoa informa o nome, clica em Ativar câmera e microfone, permite o acesso e escolhe os dispositivos. Depois clica em **Próximo · abrir palco**. O retorno do programa ocupa a área principal; câmera, microfone, tela e saída ficam acessíveis abaixo. O botão de configurações permite trocar dispositivos ou atualizar o nome sem substituir a conexão de mídia.
4. No painel Participantes, abaixo de Cenas, escolha a cena e clique em Adicionar à cena. Cada pessoa tem controles de câmera, nome, tela, microfone e volume. O nome é uma camada própria: clique nela para mover/redimensionar no canvas e escolher entre seis estilos nas Propriedades; use o olho para exibir ou ocultar.
5. Use fones. O retorno contém o áudio do estúdio e dos outros convidados, excluindo a própria voz. As trilhas internas 5, 6 e 4 são reservadas ao retorno dos três convidados; fontes do apresentador precisam participar dessas trilhas para serem ouvidas.
6. Revogar desconecta um convite. Encerrar sala invalida todos os links. Encerrar a transmissão também fecha a sala depois que a saída parar por completo. Reabrir o aplicativo exige novos convites; os componentes dos convites atuais são removidos das cenas. Fontes órfãs de versões anteriores podem ser removidas manualmente.

## Conversa interna da sala — 0.1.36

O anfitrião abre **Conversa dos participantes** no estúdio; o convidado abre **Conversa** no navegador. Este chat não entra na cena, no retorno em vídeo nem nos comentários públicos do YouTube. **Todos** envia ao grupo. Escolher uma pessoa na lista ou escrever `@nome` envia somente ao destinatário e ao remetente; uma menção ambígua ou indisponível é recusada em vez de ser enviada ao grupo. O servidor valida convite e cliente, limita mensagens a 2.000 caracteres/4.000 bytes e aceita no máximo uma por remetente a cada meio segundo. Até 200 mensagens ficam apenas na memória e são apagadas ao encerrar a sala. O teste local com três navegadores confirmou que mensagem privada entre convidados não aparece ao terceiro convidado nem no painel do anfitrião.

Na versão 0.1.37, o painel do anfitrião também pode ser arrastado pelo cabeçalho. A posição permanece durante a sessão e se ajusta aos limites da janela do estúdio.

## Conexão e segurança

O servidor escuta somente em loopback. O helper cloudflared cria um endereço HTTPS temporário para página e sinalização. A mídia usa WebRTC, diretamente quando possível; não passa automaticamente pela ponte HTTP. Quick Tunnel é um serviço de teste, sem SLA, e o endereço muda ao encerrar a sala. Não é uma infraestrutura de produção garantida.

O token aleatório de 256 bits fica no fragmento do convite e depois na sessão do navegador. As chamadas usam Bearer, validação de origem, limites de tamanho, tempo e frequência. Não há acesso remoto genérico ao motor. Cada convite aceita um navegador; o primeiro acesso expira em 12 horas. Não envie o link a pessoas não autorizadas. Revogue se houver exposição.

STUN Cloudflare é o padrão. TURN **não está configurado por padrão** nesta distribuição. Redes corporativas, NAT restritivo ou certas operadoras podem impedir conexão direta. A guia Servidor TURN aceita uma VPS própria e obtém credenciais temporárias automaticamente. A área avançada ainda aceita uma lista JSON manual de URLs TURN e credenciais temporárias, apenas em memória; nunca informe chave administrativa de provedor. Controle de franquia não está implementado.

## VPS própria para convidados — implementação local em validação

Na guia **Participantes → Servidor TURN**, informe o IPv4 público, a porta HTTPS (443 no instalador de referência) e o token de conexão. O token fica no Acesso às Chaves deste Mac; o app não armazena senha SSH. É possível importar o perfil JSON gerado pelo instalador. O perfil contém segredo: mantenha permissões privadas, não envie pelo convite e remova o arquivo de importação após salvá-lo no app.

O instalador de referência em `server/install-ubuntu.sh` prepara Ubuntu 24.04 com Nginx, certificado HTTPS por IP, Coturn e um pequeno gateway de sinalização Python. A página do convidado e a sinalização passam pelo HTTPS da VPS; câmera, tela e áudio usam WebRTC direto ou TURN, nunca o gateway HTTP. O gateway só aceita host autorizado para obter credenciais TURN de validade limitada e encaminha mensagens de convidados numa fila limitada. A configuração é por usuário/VPS, não há SSH dentro do aplicativo. Dois navegadores sintéticos neste Mac passaram pelo endereço da VPS, inclusive com candidato TURN relay obrigatório, mídia, retorno, reconexão e revogação. **Ainda não foi validado com convidados reais em redes externas diferentes nem com live longa**. Dimensione tráfego com medições reais.

## Limites e validação

Até três convidados, câmera até 1080p/30 e tela até 1080p/30 solicitados ao navegador. O navegador/rede podem negociar menos. Compartilhamento de áudio da tela não está implementado. Não há limite de horas no código, mas sessão de duas horas, redes externas distintas, Safari/Firefox, rotação de câmera móvel, Intel físico e macOS 14 real ainda precisam de validação. Use Chrome atualizado no primeiro teste.

Trocar dispositivos é uma ação do convidado. A partir da 0.1.22, uma conexão de mídia que falhou, oscilou por mais de cinco segundos ou teve a negociação encerrada tenta se refazer automaticamente com o mesmo convite e as trilhas de câmera, microfone e tela já autorizadas. Há espera crescente de até 15 segundos entre tentativas e um botão para reconectar imediatamente. O navegador precisa permanecer aberto, as trilhas ativas e o token válido. Não há ICE restart da mesma conexão: um novo peer substitui o antigo. Uma falha do Quick Tunnel que encerre a sala ainda pede nova sala/links. Desfazer/refazer e importar projeto ficam bloqueados enquanto há convites para preservar as referências de mídia. Revogar remove os componentes desse participante das cenas.

Teste automatizado: dois navegadores Chrome isolados, câmeras/telas e tons sintéticos, WebRTC real chegando à libobs, quatro fontes de vídeo e dois medidores de microfone. Análise espectral verificou retorno do outro convidado e exclusão da própria voz; revogação interrompeu a sessão. Não foi uma transmissão pública nem validação de câmera física.

Dependências fixadas em packaging/guests-lock.json: LiveKitWebRTC 150.7871.03 e cloudflared 2026.10.1 recompilado para macOS 14, arm64 e x86_64. Licenças e fontes correspondentes acompanham a distribuição.

O mesmo teste passou também pelo endereço público HTTPS do Quick Tunnel. Os dois navegadores estavam neste Mac: isso verifica o caminho público de sinalização, mas não comprova NAT/redes externas distintas nem TURN.

## Correção local do convite — 2026-10-16

A primeira preparação enviava o texto do placeholder como `deviceId.exact`, causando OverconstrainedError antes de exibir os dispositivos. Agora placeholders usam valor vazio e somente opções provenientes de enumerateDevices podem fornecer um identificador exato. A página lista opções sem abrir captura; acesso continua dependendo do clique e da permissão do navegador. Troca de dispositivo encerra a mídia anterior só depois de obter a substituta, e falha de autorização mantém a prévia existente. Mensagens distinguem recusa, dispositivo ausente/ocupado e seleção indisponível.

Convite reorganizado em prévia + controles compactos, com ativação em destaque, medidor e toggles junto ao vídeo. Desktop usa a altura útil em uma tela; celular empilha cartões, mantém seletores lado a lado e alvos de toque. Informações adicionais ficam em Privacidade do convite.

Teste `Tests/guest-onboarding.cjs` reproduziu o problema nos arquivos anteriores do HEAD e passou na nova página com dispositivos sintéticos. Sete viewports (desktop, celular e paisagem), primeira ativação, troca de câmera, toggles, recusa preservando mídia e desligamento ao sair. Capturas em `build/guest-onboarding-qa`; reprodução anterior em `build/guest-onboarding-baseline-result`. Não é validação de hardware físico, Safari/Firefox ou redes externas. Não altera a instância OBS, a sala ativa nem o aplicativo instalado; nova publicação ainda não realizada.

Validação adicional: `node Tests/guest-onboarding.cjs build/guest-onboarding-native-qa` passou com as políticas CSP/Permissions-Policy do servidor. Além das fixtures, usa getUserMedia/enumerateDevices nativos do Chrome com dispositivos de teste do próprio navegador, sem abrir hardware físico. Recusa, nova permissão, quadros de vídeo, áudio no medidor e desligamento foram verificados. Suspensão do AudioContext não mantém os controles bloqueados. Baseline em `build/guest-placeholder-baseline-result/baseline.json` confirma placeholder enviado como identificador exato. Incluído na preparação da 0.1.12.

## Conexão direta incremental — 0.1.13

A descoberta de rede não precisa terminar para começar a conexão. SDP segue imediatamente; o endpoint autenticado `/ice` troca candidatos em lotes, deduplica no peer e rejeita tentativas antigas. Polling a cada 500 ms durante conexão, 2,5 s conectado; filas limitadas a 64 candidatos por lado, 1 KiB por candidato, UUID de negociação e mesmas regras de token/origem/cliente. Mensagens diferenciam sinalização e mídia; o aviso genérico para configurar TURN foi retirado da falha do convidado.

Testes: `GuestHarness --blocked-stun` e `Tests/guest-browser.cjs`, dois Chrome/mídia sintética, STUN inacessível, sem TURN. Em loopback conectaram em 973 e 115 ms; pelo HTTPS público, 1190 e 546 ms, com `DANTE_PENDING_DISCOVERY=1` mantendo o estado de descoberta em aberto no navegador. São observações destas execuções, não benchmark de latência nem promessa de tempo de conexão. Vídeo/câmera, tela, áudio, mix-minus, revogação e rejeição de sessão antiga passaram. Suíte Swift/Python e onboarding passaram; typecheck x86_64/macOS14 passou. Evidência local: build/guest-trickle-qa. Nenhum token/IP/credencial foi incluído no relatório público.

O teste público usa dois navegadores no mesmo Mac. Rede externa do convidado, NAT distinto, hardware físico e sessões longas ainda precisam de aceitação. Quick Tunnel não resolve o caminho de mídia: [é para desenvolvimento/teste](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) e [a Cloudflare documenta restrições para servir vídeo pelo proxy público](https://developers.cloudflare.com/cloudflare-one/faq/cloudflare-tunnels-faq/#large-file-and-streaming-traffic-through-tunnel). Não transportamos mídia pelo túnel nem desativamos proteção de rede.

## Retorno e controles — 0.1.14

A página mostra o programa composto, diretamente do Dante, até 960×540/15 FPS. Não usa o player do YouTube nem altera o preset principal. Há atraso de captura, codificação e rede; não é latência zero. Silenciar retorno muda somente o que o convidado ouve, sem silenciar o microfone enviado. Câmera e microfone ficam verdes quando ativos e vermelhos quando desligados; compartilhamento fica verde quando ativo e neutro quando parado.

A cor acompanha o participante durante a sala, mesmo se o outro sair; nomes iguais não unem fontes. Componentes são associados a uma cena por participante, com transferência preservando enquadramento e estado. No modo estúdio, alterações dos itens da prévia aguardam Corte/Transição; mute/volume e dispositivos continuam controles globais. Ouvir neste Mac controla somente a monitoração do operador.

Os testes locais da 0.1.14 incluíram tela compartilhada após conexão, stop/restart, microfone mono e estéreo, quatro vídeos com dimensões reais, dois medidores, pixels do programa recebidos pelos dois convidados, análise espectral do mix-minus e controles locais. Foram usados dispositivos sintéticos em Chrome no mesmo Mac, sem transmissão pública.

## Tratamento de voz e qualidade — 0.1.17

Em **Participantes → Tratamento da voz**, habilite **Reduzir ruído de fundo** para o microfone desejado. **Automático • voz** usa RNNoise; **Manual • intensidade** usa Speex e permite ajustar a redução de 0 a 60 dB. Comece com uma redução moderada: valores fortes podem cortar partes da voz. Desligar o tratamento mantém método e intensidade, sem mudar o volume, mute ou a exclusão da própria voz no retorno. O ajuste afeta o áudio enviado à live e aos demais convidados. A captura do navegador pode ter tratamento próprio adicional.

Câmera e tela negociam H.264 quando disponível, com limites separados de bitrate e FPS e adaptação à rede. Não há taxa mínima forçada nem promessa de qualidade constante em uma conexão congestionada. Veja [decisões de mídia e limites do diagnóstico de eco](MEDIA-RESEARCH.md).
