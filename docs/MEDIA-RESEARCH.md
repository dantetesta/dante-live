# Transporte, latência e tratamento de voz

Investigação de 16/10/2026. As referências abaixo orientam decisões; nenhuma delas foi incorporada ao runtime nesta alteração.

| Referência | Utilidade para o Dante Live | Decisão atual |
|---|---|---|
| [Ant Media Server](https://github.com/ant-media/Ant-Media-Server) | Servidor de distribuição/relay com WebRTC e outros protocolos; possível caminho para convidados e público em infraestrutura própria. | Exige hospedagem, operação e avaliação das funcionalidades/licenças de cada edição. Não é um codec para inserir no app; um servidor intermediário não elimina o buffer do player YouTube. |
| [Moxygen](https://github.com/facebookexperimental/moxygen) | Implementação C++ de Media over QUIC, com publisher, subscriber e relay. Referência para transporte e descarte de mídia atrasada. | Requer um caminho de mídia e clientes compatíveis novos, além das dependências de rede. Não substitui diretamente RTMP/RTMPS ou os peers WebRTC existentes. Avaliar em protótipo isolado antes de uma migração. |
| [Stream-DiffVSR](https://jamichss.github.io/stream-diffvsr-project-page/) | Super-resolução temporal com difusão para reconstrução de vídeo. | O resultado publicado de 0,328 s/quadro em 720p numa RTX 4090 equivale a aproximadamente 3 quadros/s. Não demonstra viabilidade de 30 FPS neste Mac. Não colocar processamento desse custo no caminho de conversa ao vivo. |

## Ajustes implementados na versão 0.1.17

- Convidados: preferência por H.264 quando negociável, câmera até 3 Mbps/30 FPS, tela até 5 Mbps/15 FPS, áudio até 128 kbps. São tetos, não taxas mínimas ou garantidas. O controle de congestionamento permanece ativo; manter a resolução pode reduzir FPS sob pressão. Tela sinaliza conteúdo detalhado. H.265 é excluído da lista de preferências por colisão de payload observada entre transceivers no receptor atual; outros codecs permanecem como alternativas.
- Retorno do programa: mantém até 960×540/15 FPS, com teto solicitado de 1,5 Mbps. Vídeo recebido não usa uma segunda fila assíncrona do OBS. Esses ajustes não provam ganho de latência fim a fim nem ausência de dessincronização em redes distintas.
- Saída para a plataforma: H.264 VideoToolbox sem B-frames; x264 usa `zerolatency`. CBR e keyframes a cada dois segundos são preservados. Menos retenção de quadros pode custar eficiência de compressão; não é melhoria simultânea garantida de qualidade e banda.
- YouTube: novas preparações usam `ultraLow`; preparações salvas e eventos existentes mantêm sua configuração. Controle visível na preparação e confirmação. 4K exige Normal. O link é derivado do vídeo realmente iniciado e pode ser copiado no estúdio; não expõe a chave RTMP.
- Participantes → Tratamento da voz: redução opcional, inicialmente desligada no motor, RNNoise automático ou Speex manual (0–60 dB). Desligar preserva o ajuste para reativação; não modifica mute, volume ou trilhas. O navegador pode também aplicar seu próprio tratamento de captura.

A [documentação do YouTube](https://support.google.com/youtube/answer/7444635) informa que a maioria dos espectadores recebe menos de cinco segundos em ultrabaixa latência, com maior risco de buffering, e que 4K não é suportado nos modos baixo/ultrabaixo. Essa indicação não é uma medição do Dante. A [API de broadcasts](https://developers.google.com/youtube/v3/live/docs/liveBroadcasts) expõe `contentDetails.latencyPreference`; RTMP sozinho não muda essa preferência de um vídeo existente.

## Eco: diagnóstico ainda aberto

Dois peers sintéticos confirmam que o mix-minus exclui a voz direta de cada convidado e preserva a do outro. Isso não exclui uma cópia da voz recaptada por um microfone do anfitrião ou por uma captura de áudio do sistema.

Foi criado um teste opcional com recaptura sintética atrasada em 160 ms. A tentativa de habilitar AEC no retorno WebRTC informou processamento ativo e referência não silenciosa, mas não atingiu a supressão exigida. Essa tentativa foi retirada do código do produto. O teste continua disponível com `DANTE_ACOUSTIC_ECHO_TEST=1` e deve falhar enquanto a recaptura não for resolvida. Evidência local: `build/guest-echo-qa/reference-new/echo-result.json`. Não confundir redução de ruído com cancelamento de eco, nem anunciar a causa do problema real como comprovada.

## Limites de validação

Os testes usam dispositivos sintéticos, dois Chrome e motor nativo no mesmo Mac. Não equivalem a teste do microfone do usuário, redes remotas/NAT distintas, Safari/Firefox, Intel físico, sessão prolongada ou medição de latência até o espectador. A live e os aplicativos instalados foram preservados.
