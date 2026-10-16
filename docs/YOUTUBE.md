# YouTube no Dante Live

A chave RTMP transporta áudio/vídeo. Para criar vídeos, definir título, descrição, palavras-chave, capa, visibilidade e agendamento, o Dante usa a API oficial do YouTube com autorização Google. Não reutiliza as credenciais OAuth do OBS.

## Preparar, salvar ou agendar

1. Em **Conta YouTube**, conecte o canal.
2. Na guia **Preparar live**, preencha título, descrição, capa e visibilidade. Categoria, palavras-chave e latência ficam em uma seção expansível.
3. **Salvar na lista** mantém uma preparação local para transmitir sem horário marcado. Você pode criar outras usando **Nova live**; as anteriores continuam disponíveis em **Minhas lives**. Os campos também têm autosave.
4. **Agendar…** abre calendário e horário no fuso deste Mac. Confira canal e visibilidade e clique em **Agendar no YouTube**. Essa ação cria o vídeo e o link, mas não inicia o envio automaticamente.
5. No estúdio, clique em **Transmitir**, escolha uma preparação salva ou live agendada e confirme. Depois da preparação, a contagem **3, 2, 1** precede o início do envio.

Escolher uma preparação local em Minhas lives permite continuar editando seus dados. Uma live já criada preserva seu link e é editada no YouTube Studio. As listas são separadas por canal. Falhas de criação remota mantêm um registro para retomar sem duplicação automática.

## Tutorial em vídeo

[Assista ao tutorial do autor](https://youtu.be/WHGy0IJvG5Y). O HTML foi revisado com o manual atualizado do Dante Studio, a transcrição e as telas do vídeo, com links para seis trechos. O caminho de **Tela de permissão OAuth**, os usuários de teste, a seleção do projeto e o download imediato do JSON foram detalhados.

O vídeo configura `youtube.upload` e `youtube.readonly` para o Studio. O **Live usa `https://www.googleapis.com/auth/youtube`**: siga a etapa 5 do HTML adaptada ao Live. O vídeo termina no download; as etapas seguintes do guia mostram a importação e conexão do aplicativo. O projeto Dante Studio não foi alterado.

## Configuração inicial

O botão **Manual de integração com YouTube**, em **Configurações da live → Conta YouTube**, abre no navegador o guia HTML incluído no aplicativo. O manual pode ser lido offline; os links do Google e a autorização precisam de internet. A consulta permanece disponível mesmo enquanto os controles de conexão estão bloqueados por uma saída ativa.

Fonte do guia: [`Sources/Help/youtube-integration.html`](../Sources/Help/youtube-integration.html). O build copia somente esse recurso para `Contents/Resources/Help/`, e o empacotamento exige sua presença. É documentação destinada ao usuário, incluída por solicitação explícita; os documentos internos continuam fora do runtime. Nenhuma credencial é incluída no HTML. Checklist e impressão são locais ao navegador.

Validação local em 16/10/2026: tela SwiftUI real compilada em arm64 em aplicativo QA isolado, sem inicializar o motor e com cofre em memória vazio; botão abriu no Chrome o HTML de `Contents/Resources/Help/` com saída ativa simulada e importação bloqueada. Typecheck de todas as fontes do app passou para x86_64/macOS 14. HTML com oito etapas, âncoras válidas e recursos incorporados; cópias do projeto, Downloads e bundle QA idênticas. Sintaxe de build/empacotamento verificada. Não houve OAuth real, alteração do aplicativo instalado, novo DMG ou publicação nesta etapa; a integração foi preparada para o build 0.1.11.

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

## Biblioteca visual de lives (0.1.9)

No modo YouTube, **Transmitir** abre uma janela com as lives criadas/agendadas do canal conectado. Cada cartão mostra capa (ou indicação visual quando indisponível), título, visibilidade e data/hora no fuso do Mac. A busca filtra pelo título; Atualizar consulta novamente o YouTube. Lives concluídas não fazem parte da lista de próximas transmissões.

Selecione o cartão e clique em **Continuar**. A próxima tela confirma os dados atuais do mesmo vídeo; só **Confirmar e transmitir** prepara a conexão e inicia a contagem regressiva. Cancelar a biblioteca não transmite. A aba YouTube das configurações também abre a biblioteca pelo botão **Ver minhas lives**, para salvar uma seleção sem iniciar a transmissão.

O rascunho local fica separado dos eventos já criados. Selecioná-lo não publica nada: a criação remota continua acontecendo após confirmação. RTMP manual permanece com confirmação direta, sem biblioteca, porque a chave RTMP não oferece acesso à API de lives do canal.

## Ocultar lives somente neste Mac (0.1.11)

No menu **•••** do cartão, ou com o botão direito, escolha **Ocultar neste Mac**. A live deixa de aparecer na lista local; nenhuma exclusão, edição, cancelamento ou alteração de visibilidade é enviada ao YouTube. A preferência é salva por canal e permanece após atualizar a lista ou reabrir o aplicativo.

Marque **Mostrar ocultas** para vê-las e use **Mostrar novamente neste Mac** para restaurar cada cartão. Uma live oculta não pode ser escolhida para transmitir; se era a seleção salva, essa seleção é limpa. Ocultar não apaga o rascunho nem o registro de criação remota usado para evitar duplicações. A organização fica bloqueada durante uma operação do YouTube ou uma live acompanhada pelo app.

Validação: testes offline exercitam ausência de chamadas à API ao ocultar/restaurar, persistência após atualização e reabertura, isolamento por canal, rascunhos e reversão quando o disco falha. Isso não constitui teste de uma transmissão real.

### Correção do pacote de demonstração

A cópia isolada usada para novas capturas inicialmente recebeu o executável atualizado sem `Resources/Help/youtube-integration.html`. O recurso foi incluído e a mensagem de erro passou a distinguir arquivo ausente de falha ao abrir o navegador, com acesso alternativo ao vídeo do autor. O script oficial de build copia o HTML e o empacotamento já exige sua presença; o DMG 0.1.10 continua inalterado.
