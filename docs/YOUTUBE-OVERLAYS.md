# Chat, destaques e alertas do YouTube

Durante uma live do YouTube iniciada pelo Dante Live, o painel **Chat e destaques** permite ao anfitrião escrever e enviar uma mensagem ao chat pelo canal conectado. O limite é de 200 caracteres; cada envio custa 20 unidades de cota. O Mac limita a 100 tentativas de envio em 24 horas (até 2.000 unidades), inclusive respostas incertas. Uma URL pode ser digitada no texto, mas sua aceitação e exibição dependem das regras do YouTube. O Dante Live só limpa o rascunho após a confirmação da API. Se a resposta se perder, confira o chat no YouTube antes de tentar novamente: o aplicativo não repete o envio automaticamente.

## Antes de transmitir

1. Adicione **Chat do YouTube** ou **Destaque de comentário** em Adicionar à cena → Elementos.
2. O canvas da prévia mostra mensagens identificadas como exemplos. Elas são desenhadas somente pelo editor: nunca entram na imagem do programa, gravação ou retorno do convidado.
3. Escolha o estilo nas Propriedades. Os seis modelos principais são YouTube Clean, Vidro, Neon, Claro, Balões e Terminal; há mais seis variações. Vidro usa transparência e brilho, sem desfocar a cena atrás dele.
4. Ajuste separadamente nome, mensagem, espaço entre comentários, fonte, cores e opacidade. As miniaturas são renderizadas pelo mesmo desenhador dos cartões reais.
5. Arraste as alças laterais para mudar largura ou altura. O componente reorganiza as linhas sem mudar a escala do texto. Use **Escala geral** nas Propriedades para ampliar ou reduzir cartão, ícones e letras juntos, de 50% a 200%, com novo desenho em resolução própria. A altura mínima impede cortar a primeira linha. Posição, rotação, crop e espelhamento continuam disponíveis. Propriedades de uma fonte reutilizada afetam todas as cenas que usam essa fonte.

**Fonte do nome** e **Fonte da mensagem** abrem uma lista com busca pelas famílias instaladas neste Mac, inclusive fontes adicionadas pelo usuário. O destaque oferece fontes adicionais para identificação e valor do Super Chat. Cada trecho tem tamanho e controles de negrito, itálico e sublinhado. A família única de projetos antigos permanece como fallback. Se outra máquina não tiver a fonte escolhida, o cartão usa a fonte do sistema e mostra um aviso nas Propriedades.

## Durante a live

Durante a transmissão, a consulta rápida acontece somente quando a fonte **Chat do YouTube** está visível na cena em Programa, inclusive em uma cena aninhada visível. O intervalo pode ser de 10, 15 ou 30 segundos; o mínimo enviado pelo YouTube sempre prevalece. Com o painel Chat aberto, a atualização automática opcional consulta a cada 30 ou 60 segundos. **Consultar agora** faz uma leitura manual, respeitando a pausa exigida pelo YouTube. Com o painel fechado e sem chat visível no Programa, não há consultas de comentários. Abrir o painel no modo automático inicia a primeira consulta; iniciar apenas no modo manual pode perder mensagens antigas que o YouTube já não devolve.

O chat mostra os cartões mais recentes que cabem na área, com até aproximadamente cinco linhas por comentário. O painel mantém até 1.000 mensagens comuns recentes da sessão e informa quando as mais antigas precisam sair da fila. Cada pessoa recebe uma cor consistente de identificação e uma inicial, sem baixar a foto de perfil.

Super Chats aguardam aprovação no painel Chat. **Mostrar** publica o destaque; **Ocultar** retira. Texto longo é paginado conforme largura, altura e fonte, sem descartar seu restante. O painel usa a fonte de destaque selecionada, ou a primeira encontrada, como referência para as páginas. Em várias fontes com tamanhos diferentes, o mesmo índice pode corresponder a trechos diferentes; prefira uma fonte de destaque reutilizada.

## Painel flutuante e organização da fila

O painel Chat pode ser movido pela barra de título e coexistir com configurações, convidados, biblioteca, propriedades e outros painéis do estúdio. Fechar um painel não fecha os demais. Diálogos do sistema, como escolha de arquivos e alertas, mantêm seu comportamento nativo.

Use **Buscar por nome ou mensagem** e **Mais recentes / Mais antigos** em qualquer uma das três abas. **Super Chats** e **Conversa** mostram os itens pendentes; **Já exibidos** guarda até 500 destaques desta sessão, com tag colorida.

Cada linha pendente tem **Mostrar** e **Ocultar**. Ocultar move a mensagem imediatamente para o histórico e tira da fila. Se ela não passou pelo programa, recebe a tag **Ocultado sem ir ao ar**; não é apresentada como transmissão realizada. Retirar somente o olho da fonte ou trocar o destaque inicia o prazo de 30 segundos antes do arquivamento, cancelado se o mesmo destaque voltar ao ar. É possível mostrar novamente um item do histórico. O fluxo automático da janela de chat não é alterado pela classificação da fila de destaques.

Mensagens removidas/moderadas não reaparecem no histórico. Tudo é limpo ao encerrar a live. Nenhuma classificação é enviada ao YouTube.

## Contador e alertas

Adicione **Likes e novos inscritos** em Elementos. Nas Propriedades, habilite contador e/ou inscritos públicos, selecione um dos seis estilos prontos e edite cores, fontes, tamanhos e estilos independentes para título, contagem/nome e detalhes. O controle **Ícone de like e inscrição** ajusta o selo e o símbolo de 24 a 120 px sem mudar as letras; o espaço do cartão limita o tamanho efetivo. A largura e a altura podem ser ajustadas separadamente no canvas sem deformar o texto; **Escala geral** amplia o desenho completo. Novos componentes começam em 820 × 240 com fontes maiores. Componentes existentes preservam os valores salvos.

- Likes: total do vídeo realmente iniciado, consultado a cada 15 segundos. A primeira resposta inicializa o contador; aumentos seguintes animam o joinha. Atualizações agrupadas mostram o total mais recente, sem inventar nomes ou um evento por pessoa. Reduções do total são respeitadas.
- Inscritos: consulta de inscritos públicos recentes a cada 30 segundos. A primeira resposta é referência e não gera alertas antigos. Novidades com data posterior ao início entram numa fila de cinco segundos por aviso. O ID do canal impede repetição na mesma live, inclusive após desligar/religar alertas ou após desinscrição/reinscrição observada.
- Total do canal: consulta opcional a `channels.list?mine=true&part=statistics` a cada 30 segundos. O YouTube arredonda a contagem para baixo em três algarismos significativos; o componente a apresenta com **≈** e respeita canais que ocultam esse número.
- Novos nesta live: contagem opcional dos canais públicos novos efetivamente detectados pela consulta. É parcial e pode ficar abaixo do ganho real, inclusive quando a API limitar registros ou a opção for ativada depois do início.
- A consulta pode atrasar ou omitir pessoas; inscrições privadas não são divulgadas. O app não afirma conhecer todos os novos inscritos. Até quatro páginas de 50 registros por consulta, fila de até 200 avisos e deduplicação de até 10.000 canais por live. Não há promessa de alertas instantâneos.
- Sem fonte habilitada não há consultas de alertas. Quota/autorização insuficiente interrompe consultas afetadas e aparece nas Propriedades. Ao encerrar, fila, nomes e contagem em memória são limpos; apenas configurações visuais ficam no projeto.

A conexão OAuth do anfitrião não permite saber quem deu like. Fazer login no YouTube não equivale a autorizar individualmente o Dante Live.

## Evidência e limites

Testes locais verificam consultas autenticadas somente de leitura, primeira resposta sem alertas antigos, agrupamento/redução de likes, fila de cinco segundos, IDs repetidos, reset e cancelamento. Os desenhos são conferidos com dados fictícios e pixels reais do motor; não foi usada uma live pública ou conta bancária nestes testes. A suíte `scripts/test-chat.sh` cobre chat, alertas e renderização nativa; `Tests/CanvasGeometryTests.swift` cobre dimensões independentes com rotação/espelhamento.

Cada chamada a `liveChatMessages.list` custa 5 unidades. Em uma live de três horas, somente o chat a cada 10 segundos consumiria aproximadamente 5.400 unidades; a cada 30 segundos, 1.800. Este Mac limita o chat a 1.200 consultas (6.000 unidades) em qualquer período móvel de 24 horas e pausa a consulta ao atingir o teto. Esses valores ignoram outras funções, dispositivos e chamadas auxiliares. A cota de 10.000 unidades é por projeto/dia, e o app não conhece o consumo total externo. Não há garantia de que a cota não será excedida; erros de cota pausam o chat e aparecem no painel.

Fontes oficiais: [total de likes](https://developers.google.com/youtube/data/reference/rest/v3/videos#statistics.likeCount), [estatísticas do canal](https://developers.google.com/youtube/data/reference/rest/v3/channels#statistics.subscriberCount), [inscritos recentes](https://developers.google.com/youtube/data/reference/rest/v3/subscriptions/list?hl=en), [privacidade das inscrições](https://support.google.com/youtube/answer/7280745?hl=en-EN).
