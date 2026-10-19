# Chat, destaques e alertas do YouTube

## Antes de transmitir

1. Adicione **Chat do YouTube** ou **Destaque de comentário** em Adicionar à cena → Elementos.
2. O canvas da prévia mostra mensagens identificadas como exemplos. Elas são desenhadas somente pelo editor: nunca entram na imagem do programa, gravação ou retorno do convidado.
3. Escolha o estilo nas Propriedades. Os seis modelos principais são YouTube Clean, Vidro, Neon, Claro, Balões e Terminal; há mais seis variações. Vidro usa transparência e brilho, sem desfocar a cena atrás dele.
4. Ajuste separadamente nome, mensagem, espaço entre comentários, fonte, cores e opacidade. As miniaturas são renderizadas pelo mesmo desenhador dos cartões reais.
5. Arraste as alças laterais para mudar largura ou altura. O componente reorganiza as linhas sem mudar a escala do texto. A altura mínima impede cortar a primeira linha. Posição, rotação, crop e espelhamento continuam disponíveis. Propriedades de uma fonte reutilizada afetam todas as cenas que usam essa fonte.

**Fonte** abre uma lista com busca pelas famílias instaladas neste Mac, inclusive fontes adicionadas pelo usuário. O nome escolhido é salvo no projeto. Se outra máquina não tiver essa fonte, o cartão usa a fonte do sistema e mostra um aviso nas Propriedades.

## Durante a live

O chat conectado recebe as mensagens comuns automaticamente. Mostra os cartões mais recentes que cabem na área, com até aproximadamente cinco linhas por comentário. O painel mantém o texto completo. Cada pessoa recebe uma cor consistente de identificação e uma inicial, sem baixar a foto de perfil.

Super Chats aguardam aprovação no painel Chat. **Mostrar** publica o destaque; **Ocultar** retira. Texto longo é paginado conforme largura, altura e fonte, sem descartar seu restante. O painel usa a fonte de destaque selecionada, ou a primeira encontrada, como referência para as páginas. Em várias fontes com tamanhos diferentes, o mesmo índice pode corresponder a trechos diferentes; prefira uma fonte de destaque reutilizada.

## Painel flutuante e organização da fila

O painel Chat pode ser movido pela barra de título e coexistir com configurações, convidados, biblioteca, propriedades e outros painéis do estúdio. Fechar um painel não fecha os demais. Diálogos do sistema, como escolha de arquivos e alertas, mantêm seu comportamento nativo.

Use **Buscar por nome ou mensagem** e **Mais recentes / Mais antigos** em qualquer uma das três abas. **Super Chats** e **Conversa** mostram os itens pendentes; **Já exibidos** guarda até 500 destaques desta sessão, com tag colorida.

Cada linha pendente tem **Mostrar** e **Ocultar**. Ocultar move a mensagem imediatamente para o histórico e tira da fila. Se ela não passou pelo programa, recebe a tag **Ocultado sem ir ao ar**; não é apresentada como transmissão realizada. Retirar somente o olho da fonte ou trocar o destaque inicia o prazo de 30 segundos antes do arquivamento, cancelado se o mesmo destaque voltar ao ar. É possível mostrar novamente um item do histórico. O fluxo automático da janela de chat não é alterado pela classificação da fila de destaques.

Mensagens removidas/moderadas não reaparecem no histórico. Tudo é limpo ao encerrar a live. Nenhuma classificação é enviada ao YouTube.

## Contador e alertas

Adicione **Likes e novos inscritos** em Elementos. Nas Propriedades, habilite contador e/ou inscritos públicos, selecione um dos seis estilos prontos e edite cores, fonte e tamanhos do título, da contagem e dos detalhes. A largura e a altura podem ser ajustadas separadamente no canvas sem deformar o texto.

- Likes: total do vídeo realmente iniciado, consultado a cada 15 segundos. A primeira resposta inicializa o contador; aumentos seguintes animam o joinha. Atualizações agrupadas mostram o total mais recente, sem inventar nomes ou um evento por pessoa. Reduções do total são respeitadas.
- Inscritos: consulta de inscritos públicos recentes a cada 30 segundos. A primeira resposta é referência e não gera alertas antigos. Novidades com data posterior ao início entram numa fila de cinco segundos por aviso. O ID do canal impede repetição na mesma live, inclusive após desligar/religar alertas ou após desinscrição/reinscrição observada.
- Total do canal: consulta opcional a `channels.list?mine=true&part=statistics` a cada 30 segundos. O YouTube arredonda a contagem para baixo em três algarismos significativos; o componente a apresenta com **≈** e respeita canais que ocultam esse número.
- Novos nesta live: contagem opcional dos canais públicos novos efetivamente detectados pela consulta. É parcial e pode ficar abaixo do ganho real, inclusive quando a API limitar registros ou a opção for ativada depois do início.
- A consulta pode atrasar ou omitir pessoas; inscrições privadas não são divulgadas. O app não afirma conhecer todos os novos inscritos. Até quatro páginas de 50 registros por consulta, fila de até 200 avisos e deduplicação de até 10.000 canais por live. Não há promessa de alertas instantâneos.
- Sem fonte habilitada não há consultas de alertas. Quota/autorização insuficiente interrompe consultas afetadas e aparece nas Propriedades. Ao encerrar, fila, nomes e contagem em memória são limpos; apenas configurações visuais ficam no projeto.

A conexão OAuth do anfitrião não permite saber quem deu like. Fazer login no YouTube não equivale a autorizar individualmente o Dante Live.

## Evidência e limites

Testes locais verificam consultas autenticadas somente de leitura, primeira resposta sem alertas antigos, agrupamento/redução de likes, fila de cinco segundos, IDs repetidos, reset e cancelamento. Os desenhos são conferidos com dados fictícios e pixels reais do motor; não foi usada uma live pública ou conta bancária nestes testes. A suíte `scripts/test-chat.sh` cobre chat, alertas e renderização nativa; `Tests/CanvasGeometryTests.swift` cobre dimensões independentes com rotação/espelhamento.

Fontes oficiais: [total de likes](https://developers.google.com/youtube/data/reference/rest/v3/videos#statistics.likeCount), [estatísticas do canal](https://developers.google.com/youtube/data/reference/rest/v3/channels#statistics.subscriberCount), [inscritos recentes](https://developers.google.com/youtube/data/reference/rest/v3/subscriptions/list?hl=en), [privacidade das inscrições](https://support.google.com/youtube/answer/7280745?hl=en-EN).
