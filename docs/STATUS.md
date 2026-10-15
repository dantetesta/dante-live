# Estado do projeto

Release experimental atual: **0.1.4 (5)**, com aplicação automática das propriedades, ordenação das fontes por arrasto e menu de contexto ampliado. Convidados continuam pendentes. O objetivo é um estúdio audiovisual nativo, com evolução em direção à cobertura funcional do OBS para Mac. Equivalência completa ainda não foi atingida.

| Área | Estado atual |
|---|---|
| Interface | SwiftUI/AppKit, português, painéis redimensionáveis, modo estúdio |
| Cenas e fontes | Criar, duplicar, renomear, ordenar por arrasto, visibilidade, bloqueio e reuso |
| Editor | Seleção única, arrasto, resize proporcional, campos de transformação, crop, ajuste e centralização |
| Captura | Integração de módulos de tela, câmera e áudio; cobertura de dispositivos ainda parcial |
| Mixer | Volume, mute, medidores, filtros e parâmetros de sincronização |
| Produção | Corte/fade, gravação MKV, RTMP/RTMPS manual e replay |
| Presets | 1080p, 1440p e 2160p com 30/60 FPS; política de bitrate baseada no upload |
| Projeto | Salvamento atômico, backup, recuperação e exportação/importação de JSON compatível |
| Conexões | Keychain opcional; servidor RTMP e múltiplas conexões nomeadas ainda sem persistência completa |
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
