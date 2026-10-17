# Chat, destaques e alertas do YouTube

## Antes de transmitir

1. Adicione **Chat do YouTube** ou **Destaque de comentário** em Adicionar à cena → Elementos.
2. O canvas da prévia mostra mensagens identificadas como exemplos. Elas são desenhadas somente pelo editor: nunca entram na imagem do programa, gravação ou retorno do convidado.
3. Escolha o estilo nas Propriedades. Os seis modelos principais são YouTube Clean, Vidro, Neon, Claro, Balões e Terminal; há mais seis variações. Vidro usa transparência e brilho, sem desfocar a cena atrás dele.
4. Ajuste separadamente nome, mensagem, espaço entre comentários, fonte, cores e opacidade. As miniaturas são renderizadas pelo mesmo desenhador dos cartões reais.
5. Arraste as alças laterais para mudar largura ou altura. O componente reorganiza as linhas sem mudar a escala do texto. A altura mínima impede cortar a primeira linha. Posição, rotação, crop e espelhamento continuam disponíveis. Propriedades de uma fonte reutilizada afetam todas as cenas que usam essa fonte.

## Durante a live

O chat conectado recebe as mensagens comuns automaticamente. Mostra os cartões mais recentes que cabem na área, com até aproximadamente cinco linhas por comentário. O painel mantém o texto completo. Cada pessoa recebe uma cor consistente de identificação e uma inicial, sem baixar a foto de perfil.

Super Chats aguardam aprovação no painel Chat. **Mostrar** publica o destaque; **Ocultar** retira. Texto longo é paginado conforme largura, altura e fonte, sem descartar seu restante. O painel usa a fonte de destaque selecionada, ou a primeira encontrada, como referência para as páginas. Em várias fontes com tamanhos diferentes, o mesmo índice pode corresponder a trechos diferentes; prefira uma fonte de destaque reutilizada.

## Contador e alertas

Adicione **Likes e novos inscritos** em Elementos. Nas Propriedades, habilite contador e/ou inscritos públicos. Posicione e redimensione no canvas.

- Likes: total do vídeo realmente iniciado, consultado a cada 15 segundos. A primeira resposta inicializa o contador; aumentos seguintes animam o joinha. Atualizações agrupadas mostram o total mais recente, sem inventar nomes ou um evento por pessoa. Reduções do total são respeitadas.
- Inscritos: consulta de inscritos públicos recentes a cada 30 segundos. A primeira resposta é referência e não gera alertas antigos. Novidades com data posterior ao início entram numa fila de cinco segundos por aviso. O ID do canal impede repetição na mesma live, inclusive após desligar/religar alertas ou após desinscrição/reinscrição observada.
- A consulta pode atrasar ou omitir pessoas; inscrições privadas não são divulgadas. O app não afirma conhecer todos os novos inscritos. Até quatro páginas de 50 registros por consulta, fila de até 200 avisos e deduplicação de até 10.000 canais por live. Não há promessa de alertas instantâneos.
- Sem fonte habilitada não há consultas de alertas. Quota/autorização insuficiente interrompe consultas afetadas e aparece nas Propriedades. Ao encerrar, fila, nomes e contagem em memória são limpos; apenas configurações visuais ficam no projeto.

A conexão OAuth do anfitrião não permite saber quem deu like. Fazer login no YouTube não equivale a autorizar individualmente o Dante Live.

## Evidência e limites

Testes locais verificam consultas autenticadas somente de leitura, primeira resposta sem alertas antigos, agrupamento/redução de likes, fila de cinco segundos, IDs repetidos, reset e cancelamento. Os desenhos são conferidos com dados fictícios e pixels reais do motor; não foi usada uma live pública ou conta bancária nestes testes. A suíte `scripts/test-chat.sh` cobre chat, alertas e renderização nativa; `Tests/CanvasGeometryTests.swift` cobre dimensões independentes com rotação/espelhamento.

Fontes oficiais: [total de likes](https://developers.google.com/youtube/data/reference/rest/v3/videos#statistics.likeCount), [rating do usuário autorizado](https://developers.google.com/youtube/v3/guides/implementation/ratings), [inscritos recentes](https://developers.google.com/youtube/data/reference/rest/v3/subscriptions/list?hl=en), [privacidade das inscrições](https://support.google.com/youtube/answer/7280745?hl=en-EN).
