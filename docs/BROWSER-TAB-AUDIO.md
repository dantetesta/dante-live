# Áudio de uma aba do Chrome

Na cena, clique em **Adicionar fonte → Áudio → Áudio de aba do navegador**. O Dante abre uma página local no Google Chrome. Nela, clique em **Escolher aba**, selecione **Aba do Chrome**, escolha a aba desejada e marque **Compartilhar áudio da aba**. O som entra no mixer como uma fonte própria, com volume, mudo e monitoramento. Mantenha a página de captura aberta. Para trocar de aba ou reconectar, use **Escolher ou trocar aba…** nas propriedades da fonte.

Se já houver uma fonte **Áudio do Mac** capturando o Google Chrome inteiro, silencie ou remova essa fonte para evitar som duplicado. O método por aplicativo do macOS continua misturando as abas; ele não passa a isolar áudio quando uma janela de vídeo é selecionada.

A escolha da aba é uma permissão temporária do navegador e precisa ser repetida após reiniciar o Dante. O vídeo da aba não é adicionado à cena por este recurso. O Dante aceita apenas uma aba com trilha de áudio; se o usuário selecionar janela ou tela, a captura é recusada. A conexão roda em `127.0.0.1` com token aleatório por sessão e não usa extensão, conta, VPS ou serviço externo.

Os testes automatizados verificam fluxo JavaScript com escolhas simuladas, rejeição de janela/ausência de áudio, token inválido, áudio PCM sintético de Chrome isolado chegando ao medidor libobs e silêncio após parar. Eles não substituem uma escolha manual real da aba, teste de sincronismo durante uma live longa ou validação de Intel físico.

Referências de plataforma: [captura de tela e áudio no Chrome](https://developer.chrome.com/docs/extensions/how-to/web-platform/screen-capture), [opções do seletor de compartilhamento](https://developer.chrome.com/docs/web-platform/screen-sharing-controls) e [getDisplayMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getDisplayMedia).
