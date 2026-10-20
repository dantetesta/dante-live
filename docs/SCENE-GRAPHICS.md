# Faixa de texto animada e QR Code

Em Adicionar à cena → Elementos, escolha Faixa de texto animada ou QR Code. São fontes nativas editáveis, salvas no projeto, com posição, escala, olho, crop e filtros da cena. No modo estúdio, mudanças de conteúdo ficam na prévia até Corte/Transição.

## Faixa de texto animada

Entra no rodapé ocupando a largura do canvas. Nas Propriedades: texto de até 250 caracteres, altura 40–320 px, família/tamanho da fonte, negrito, itálico e cores da faixa/letra. O seletor de fonte busca as famílias instaladas no Mac. URLs são texto visível, não links clicáveis dentro do vídeo.

Em **Rolagem**, o texto inteiro corre em repetição a 0–500 px/s, da direita para a esquerda ou no sentido inverso. Quebras de linha viram espaços; velocidade zero deixa o texto parado. Em **Frases com slide**, cada linha não vazia vira uma frase. Ela permanece pelo intervalo escolhido (1–30 segundos) e a seguinte entra por baixo ou por cima; linhas longas se ajustam à área disponível. A troca de modo não apaga o texto.

O fundo aceita uma cor com opacidade própria ou gradiente de duas cores. O gradiente pode correr na horizontal ou vertical, nos dois sentidos, com pontos inicial e final de transição e opacidade independente por cor. Transparência permite ver as fontes que estão abaixo da faixa na cena. Configurações antigas continuam com cor sólida, opaca e rolagem da direita para a esquerda.

Rasterização somente em alterações; texturas em blocos limitados, movimento e recorte feitos pelo motor gráfico. Nenhum navegador, serviço ou fonte remota é necessário. O modo de frases guarda apenas o texto do projeto, não um histórico de exibições.

## QR Code

Escolha Link / site, Texto ou Pix. Preencha o conteúdo, selecione Clássico, Arredondado ou Pontos, escolha cores e opcionalmente um logo PNG/JPEG. Clique em Gerar e aplicar QR Code. Enquanto edita, o QR aplicado anteriormente permanece na cena; o aviso de alterações pendentes identifica isso. O aplicativo testa a leitura nativa e só aplica se recuperar exatamente o conteúdo gerado. Contraste insuficiente é recusado. O logo é reduzido e o código preserva margem clara e correção de erros alta.

Arraste e redimensione no canvas. Preserve a proporção quadrada, a margem e tamanho suficiente na resolução final; compressão do streaming e tela do espectador afetam a leitura. O teste local não garante todos os celulares ou apps bancários.

### Pix

QR estático BR Code: chave cadastrada (e-mail, telefone internacional, CPF, CNPJ numérico/alfanumérico ou aleatória), nome do recebedor, cidade e valor opcional. Sem valor, o pagador informa a quantia no aplicativo bancário. Formato da chave, dígitos verificadores CPF/CNPJ, limites TLV e CRC16 são validados localmente. Nome/cidade com acentos são normalizados para o padrão.

O aplicativo não consulta o DICT, não prova cadastro/titularidade da chave, não confirma recebimentos e não cria cobranças dinâmicas. O banco consulta o titular e apresenta seus dados ao pagador. Leia com o aplicativo do banco e confira o recebedor antes de divulgar. Uma câmera genérica pode apenas reconhecer o conteúdo; abertura direta do banco depende do leitor. Chave e dados do recebedor fazem parte do QR e do projeto salvo por escolha do operador.

## Implementação e testes

Core Image/CIQRCodeGenerator e Vision nativos do macOS; sem biblioteca ou serviço pago. A biblioteca livre [dagronf/QRCode (MIT)](https://github.com/dagronf/QRCode) foi avaliada como referência, mas não incorporada. Base de Pix: [Manual BCB 2.10.0](https://www.bcb.gov.br/content/estabilidadefinanceira/pix/Regulamento_Pix/II_ManualdePadroesparaIniciacaodoPix.pdf), exemplo estático da seção 2.6.3; [CNPJ alfanumérico — Receita Federal](https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/documentos-tecnicos/cnpj/manual-dv-cnpj.pdf).

`bash scripts/test-scene-graphics.sh` verifica vetor oficial Pix/CRC, valores decimais, validação de entradas, 18 combinações de leitura QR, pixels de programa, OCR da faixa, movimento, altura, persistência, formato inválido e isolamento do modo estúdio. Fixtures usam dados fictícios sem enviar pagamentos. Capturas locais dos controles em claro/escuro; sem validação de pagamento real ou hardware Intel.
