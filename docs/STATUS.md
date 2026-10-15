# Estado do projeto

Build local atual: **0.1.2 (3)**, recompilação da base 0.1.1 com atalho Aplicativos no DMG. Não acrescenta convidados nem novas funcionalidades de edição. O objetivo é um estúdio audiovisual nativo, com evolução em direção à cobertura funcional do OBS para Mac. Equivalência completa ainda não foi atingida.

| Área | Estado atual |
|---|---|
| Interface | SwiftUI/AppKit, português, painéis redimensionáveis, modo estúdio |
| Cenas e fontes | Criar, duplicar, renomear, ordenar, visibilidade, bloqueio e reuso |
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
| Editor avançado | Grupos, seleção múltipla, guias completas, modal genérico e drag-and-drop de camadas pendentes |
| Distribuição | Scripts locais; sem release pública de instalador/notarização |

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
