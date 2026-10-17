# Faixa rolante e QR Code

Em Adicionar à cena → Elementos, escolha Faixa de texto rolante ou QR Code. São fontes nativas editáveis, salvas no projeto, com posição, escala, olho, crop e filtros da cena. No modo estúdio, mudanças de conteúdo ficam na prévia até Corte/Transição.

## Faixa de texto rolante

Entra no rodapé ocupando a largura do canvas. Nas Propriedades: texto de até 250 caracteres, altura 40–320 px, velocidade 0–500 px/s, família/tamanho da fonte, negrito, itálico e cores da faixa/letra. Zero deixa o texto parado; o restante rola da direita para a esquerda em repetição. A letra se ajusta para caber em faixas baixas. URLs são texto visível, não links clicáveis dentro do vídeo.

Rasterização somente em alterações; texturas em blocos limitados, movimento e recorte feitos pelo motor gráfico. Nenhum navegador, serviço ou fonte remota é necessário.

## QR Code

Escolha Link / site, Texto ou Pix. Preencha o conteúdo, selecione Clássico, Arredondado ou Pontos, escolha cores e opcionalmente um logo PNG/JPEG. Clique em Gerar e aplicar QR Code. Enquanto edita, o QR aplicado anteriormente permanece na cena; o aviso de alterações pendentes identifica isso. O aplicativo testa a leitura nativa e só aplica se recuperar exatamente o conteúdo gerado. Contraste insuficiente é recusado. O logo é reduzido e o código preserva margem clara e correção de erros alta.

Arraste e redimensione no canvas. Preserve a proporção quadrada, a margem e tamanho suficiente na resolução final; compressão do streaming e tela do espectador afetam a leitura. O teste local não garante todos os celulares ou apps bancários.

### Pix

QR estático BR Code: chave cadastrada (e-mail, telefone internacional, CPF, CNPJ numérico/alfanumérico ou aleatória), nome do recebedor, cidade e valor opcional. Sem valor, o pagador informa a quantia no aplicativo bancário. Formato da chave, dígitos verificadores CPF/CNPJ, limites TLV e CRC16 são validados localmente. Nome/cidade com acentos são normalizados para o padrão.

O aplicativo não consulta o DICT, não prova cadastro/titularidade da chave, não confirma recebimentos e não cria cobranças dinâmicas. O banco consulta o titular e apresenta seus dados ao pagador. Leia com o aplicativo do banco e confira o recebedor antes de divulgar. Uma câmera genérica pode apenas reconhecer o conteúdo; abertura direta do banco depende do leitor. Chave e dados do recebedor fazem parte do QR e do projeto salvo por escolha do operador.

## Implementação e testes

Core Image/CIQRCodeGenerator e Vision nativos do macOS; sem biblioteca ou serviço pago. A biblioteca livre [dagronf/QRCode (MIT)](https://github.com/dagronf/QRCode) foi avaliada como referência, mas não incorporada. Base de Pix: [Manual BCB 2.10.0](https://www.bcb.gov.br/content/estabilidadefinanceira/pix/Regulamento_Pix/II_ManualdePadroesparaIniciacaodoPix.pdf), exemplo estático da seção 2.6.3; [CNPJ alfanumérico — Receita Federal](https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/documentos-tecnicos/cnpj/manual-dv-cnpj.pdf).

`bash scripts/test-scene-graphics.sh` verifica vetor oficial Pix/CRC, valores decimais, validação de entradas, 18 combinações de leitura QR, pixels de programa, OCR da faixa, movimento, altura, persistência, formato inválido e isolamento do modo estúdio. Fixtures usam dados fictícios sem enviar pagamentos. Capturas locais dos controles em claro/escuro; sem validação de pagamento real ou hardware Intel.
