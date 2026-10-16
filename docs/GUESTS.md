# Convidados por convite — experimental, 0.1.9

## Como usar

1. No topo do estúdio, clique no ícone de convidar participantes e em Convidar.
2. Copie o link e envie apenas à pessoa convidada. São dois convidados simultâneos, além do apresentador.
3. No navegador, a pessoa informa o nome, clica em Ativar câmera e microfone, permite o acesso no navegador e escolhe os dispositivos e, se quiser, compartilha uma tela. Depois clica em Entrar no estúdio.
4. No Dante, use Colocar na cena e Inserir tela. Câmera, tela e microfone são fontes separadas. Volume/mute ficam no mixer; visibilidade e enquadramento, nas fontes.
5. Use fones. O retorno contém o áudio do estúdio e do outro convidado, excluindo a própria voz. As trilhas internas 5/6 são reservadas ao retorno de convidados; fontes do apresentador precisam participar dessas trilhas para serem ouvidas.
6. Revogar desconecta um convite. Encerrar sala invalida todos os links. Reabrir o aplicativo exige novos convites; as fontes antigas permanecem vazias no projeto.

## Conexão e segurança

O servidor escuta somente em loopback. O helper cloudflared cria um endereço HTTPS temporário para página e sinalização. A mídia usa WebRTC, diretamente quando possível; não passa automaticamente pela ponte HTTP. Quick Tunnel é um serviço de teste, sem SLA, e o endereço muda ao encerrar a sala. Não é uma infraestrutura de produção garantida.

O token aleatório de 256 bits fica no fragmento do convite e depois na sessão do navegador. As chamadas usam Bearer, validação de origem, limites de tamanho, tempo e frequência. Não há acesso remoto genérico ao motor. Cada convite aceita um navegador; o primeiro acesso expira em 12 horas. Não envie o link a pessoas não autorizadas. Revogue se houver exposição.

STUN Cloudflare é o padrão. TURN **não está configurado** nesta distribuição. Redes corporativas, NAT restritivo ou certas operadoras podem impedir conexão direta. A área avançada aceita uma lista JSON de URLs TURN e credenciais temporárias, apenas em memória; nunca informe chave administrativa de provedor. Provisionamento de conta, renovação automática de credenciais TURN e controle de franquia não estão implementados.

## Limites e validação

Dois convidados, câmera até 1080p/30 e tela até 1080p/30 solicitados ao navegador. O navegador/rede podem negociar menos. Compartilhamento de áudio da tela não está implementado. Não há limite de horas no código, mas sessão de duas horas, redes externas distintas, relay TURN, Safari/Firefox, rotação de câmera móvel, Intel físico e macOS 14 real ainda precisam de validação. Use Chrome atualizado no primeiro teste.

Trocar dispositivos e reconectar são ações do convidado. Não há recuperação automática por ICE restart. Queda da ponte pede nova sala/links. Desfazer/refazer e importar projeto ficam bloqueados enquanto há convites para preservar as referências de mídia. Revogar não remove automaticamente fontes já adicionadas à cena.

Teste automatizado: dois navegadores Chrome isolados, câmeras/telas e tons sintéticos, WebRTC real chegando à libobs, quatro fontes de vídeo e dois medidores de microfone. Análise espectral verificou retorno do outro convidado e exclusão da própria voz; revogação interrompeu a sessão. Não foi uma transmissão pública nem validação de câmera física.

Dependências fixadas em packaging/guests-lock.json: LiveKitWebRTC 150.7871.03 e cloudflared 2026.10.1 recompilado para macOS 14, arm64 e x86_64. Licenças e fontes correspondentes acompanham a distribuição.

O mesmo teste passou também pelo endereço público HTTPS do Quick Tunnel. Os dois navegadores estavam neste Mac: isso verifica o caminho público de sinalização, mas não comprova NAT/redes externas distintas nem TURN.

## Correção local do convite — 2026-10-16

A primeira preparação enviava o texto do placeholder como `deviceId.exact`, causando OverconstrainedError antes de exibir os dispositivos. Agora placeholders usam valor vazio e somente opções provenientes de enumerateDevices podem fornecer um identificador exato. A página lista opções sem abrir captura; acesso continua dependendo do clique e da permissão do navegador. Troca de dispositivo encerra a mídia anterior só depois de obter a substituta, e falha de autorização mantém a prévia existente. Mensagens distinguem recusa, dispositivo ausente/ocupado e seleção indisponível.

Convite reorganizado em prévia + controles compactos, com ativação em destaque, medidor e toggles junto ao vídeo. Desktop usa a altura útil em uma tela; celular empilha cartões, mantém seletores lado a lado e alvos de toque. Informações adicionais ficam em Privacidade do convite.

Teste `Tests/guest-onboarding.cjs` reproduziu o problema nos arquivos anteriores do HEAD e passou na nova página com dispositivos sintéticos. Sete viewports (desktop, celular e paisagem), primeira ativação, troca de câmera, toggles, recusa preservando mídia e desligamento ao sair. Capturas em `build/guest-onboarding-qa`; reprodução anterior em `build/guest-onboarding-baseline-result`. Não é validação de hardware físico, Safari/Firefox ou redes externas. Não altera a instância OBS, a sala ativa nem o aplicativo instalado; nova publicação ainda não realizada.

Validação adicional: `node Tests/guest-onboarding.cjs build/guest-onboarding-native-qa` passou com as políticas CSP/Permissions-Policy do servidor. Além das fixtures, usa getUserMedia/enumerateDevices nativos do Chrome com dispositivos de teste do próprio navegador, sem abrir hardware físico. Recusa, nova permissão, quadros de vídeo, áudio no medidor e desligamento foram verificados. Suspensão do AudioContext não mantém os controles bloqueados. Baseline em `build/guest-placeholder-baseline-result/baseline.json` confirma placeholder enviado como identificador exato. Incluído na preparação da 0.1.12.
