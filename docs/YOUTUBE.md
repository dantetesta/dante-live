# YouTube no Dante Live

A chave RTMP transporta áudio/vídeo. Para criar vídeos, definir título, descrição, palavras-chave, capa, visibilidade e agendamento, o Dante usa a API oficial do YouTube com autorização Google. Não reutiliza as credenciais OAuth do OBS.

## Configuração inicial

1. No Google Cloud, crie ou selecione um projeto e habilite **YouTube Data API v3**.
2. Configure a tela de consentimento Google Auth Platform e, se estiver em teste, inclua sua conta como usuário de teste.
3. Crie um cliente OAuth **Aplicativo para computador** e baixe seu JSON.
4. Em Dante → Configurações → YouTube, clique em **Importar configuração Google** e escolha esse arquivo. Não coloque o JSON no repositório nem envie suas credenciais por mensagens.
5. Clique em **Conectar canal**, autorize no navegador e confira o nome do canal recuperado. Para outros canais, conecte novamente e selecione a identidade correta no Google.
6. Ative **Usar YouTube ao clicar em Transmitir**. O modo manual continua disponível na aba Conexão.

O aplicativo armazena tokens e configuração Google no Acesso às Chaves deste Mac. O JSON de preferências não contém esses segredos. Desconectar remove a conexão local, sem apagar vídeos. A autorização também pode ser revogada nas permissões da sua Conta Google.

Projetos Google em estado Testing podem exigir novo login depois de sete dias. Distribuição geral de uma integração Google exige configurar adequadamente consentimento, políticas e verificação do próprio projeto; o DMG não contém um cliente Google compartilhado. [Documentação OAuth](https://developers.google.com/identity/protocols/oauth2).

## Começar na hora

Selecione Novo rascunho, preencha os dados e escolha a capa JPEG/PNG de até 2 MB. As edições ficam salvas localmente. Feche as configurações, clique em Transmitir e confira canal, título, capa e visibilidade. A confirmação cria a live, prepara a conexão e inicia o envio após 3–2–1. Falhas são mostradas; sucesso não é simulado.

## Agendar e usar o mesmo link

Preencha os dados e a data/hora, clique em Criar live agendada e confirme. Isso cria o vídeo no YouTube e disponibiliza o link, sem transmitir. Quando quiser começar, selecione essa live na lista e clique em Transmitir. O Dante recupera o stream vinculado àquele vídeo e usa sua ingestão: o ID/link permanece o mesmo.

Agendar não faz o Mac ligar, abrir o Dante ou transmitir sozinho. É necessário iniciar pelo estúdio. Para editar título, capa, horário ou outros dados de uma live já criada, use o YouTube Studio e atualize a lista no Dante. Itens existentes herdam as definições do YouTube; o rascunho local não os sobrescreve.

## Falhas e limites desta versão

- Uma criação confirmada tem seu ID salvo antes das próximas etapas. Repetir a preparação retoma esse vídeo quando possível.
- Se uma resposta de criação se perder, o Dante bloqueia a repetição automática. Atualize a lista e confira o YouTube Studio antes de criar outro rascunho.
- Se os dados de um rascunho parcialmente criado forem alterados, selecione o vídeo existente e ajuste no Studio; evite criar cópias por engano.
- O status ENVIANDO / AGUARDANDO YOUTUBE distingue RTMP conectado do estado live confirmado pela API. Confira a página do vídeo para validar imagem e som recebidos.
- Encerrar live para o envio e solicita complete ao YouTube para o evento iniciado pelo Dante. Se a API falhar, finalize no Studio.
- Categoria usa uma seleção inicial de categorias comuns; opções e políticas adicionais do YouTube permanecem no Studio.
- A integração tem testes offline de contratos, falhas e persistência. **Login, agendamento e transmissão vinculada em conta real ainda não foram validados nesta release.** RTMP manual tem relato de teste funcional do mantenedor.

## Referência OBS e API

Referência fixada OBS Studio 32.2.2: `frontend/dialogs/OBSYoutubeActions.cpp`, `frontend/utility/YoutubeApiWrappers.cpp`, `frontend/oauth/YoutubeAuth.cpp`. O frontend Qt não é incorporado.

[Fluxo oficial de lives](https://developers.google.com/youtube/data/live/getting-started) · [Vínculo broadcast/stream](https://developers.google.com/youtube/v3/live/docs/liveBroadcasts/bind) · [OAuth desktop](https://developers.google.com/identity/protocols/oauth2/native-app).
