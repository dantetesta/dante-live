# Estado do projeto

Release experimental atual: **0.1.5 (6)**. Foco exclusivo em produção de lives para Mac: configurações persistentes em abas, presets automáticos e personalizados, início pelo estúdio com contagem regressiva e alerta de microfone sem sinal. Gravação de arquivos e replay buffer foram retirados da aplicação por decisão de produto. Convidados continuam pendentes.

| Área | Estado atual |
|---|---|
| Interface | SwiftUI/AppKit, português, painéis redimensionáveis, modo estúdio |
| Cenas e fontes | Criar, duplicar, renomear, ordenar por arrasto, visibilidade, bloqueio e reuso |
| Editor | Seleção única, arrasto, resize proporcional, campos de transformação, crop, ajuste e centralização |
| Captura | Integração de módulos de tela, câmera e áudio; cobertura de dispositivos ainda parcial |
| Mixer | Volume, mute, medidores, filtros e parâmetros de sincronização |
| Produção | Corte/fade, RTMP/RTMPS manual e contagem regressiva cancelável |
| Presets | 1080p, 1440p e 2160p automáticos; presets personalizados com nome, resolução/FPS/encoder/bitrates |
| Projeto | Salvamento atômico, backup, recuperação e exportação/importação de JSON compatível |
| Conexões | Servidor RTMP persistente e Keychain opcional; múltiplas conexões nomeadas pendentes |
| Convidados por link | Em preparação; não implementado no snapshot publicado |
| YouTube | Envio RTMP manual; login, título, descrição, capa e visibilidade via API ainda ausentes |
| Outros destinos simultâneos | Fora da prioridade atual; não implementado |
| Browser e câmera virtual | Pendentes; nenhum módulo Qt carregado |
| Editor avançado | Propriedades em modal e drag-and-drop de camadas disponíveis; grupos, seleção múltipla e guias completas pendentes |
| Distribuição | DMG experimental público, fontes e checksums; assinatura ad hoc, sem notarização |

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

Há relato de lag no preview/modo estúdio ainda sem correção medida. Não anunciamos redução percentual de consumo nem latência zero.

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
