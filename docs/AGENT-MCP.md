# Dante Live por MCP local

Revisão da 0.1.38: a remoção de perfis pertence ao gestor nativo e não é exposta por MCP. O contrato de cenas/fontes, suas validações e os bloqueios durante operações ativas permanecem. A conversa dos participantes em janela separada também não altera ferramentas ou autorizações MCP. A validação do executável empacotado é registrada em STATUS.md.

O Dante Live pode expor ferramentas de edição de cenas para clientes compatíveis com MCP por **stdio**. A ponte é um executável nativo dentro do aplicativo; ela se conecta ao estúdio por um socket Unix privado do usuário. Não há porta HTTP de controle, token remoto ou acesso SSH.

1. Abra o Dante Live e vá a **Dante Live → Preferências**.
2. Ative **Permitir edição local por IA (MCP)**. O estado deve mostrar **Conexão local ativa**.
3. Clique em **Copiar configuração MCP** e inclua o JSON copiado na configuração de servidores MCP do seu cliente. O caminho do comando corresponde à instalação do aplicativo que você abriu. Se mover o app, copie a configuração de novo.
4. Reinicie ou recarregue a conexão MCP do cliente. O Dante Live precisa permanecer aberto.

Um pedido útil para a IA: “Liste as cenas e os tipos de fonte disponíveis; crie uma cena chamada Entrevista com fundo, título e QR Code. Mostre o plano antes de editar, faça as alterações e leia os elementos da cena para conferir as posições.”

Ferramentas disponíveis: `studio_overview`, `scene_items`, `source_types`, `source_options`, `scene_create`, `scene_rename`, `scene_select`, `source_add`, `source_update`, `source_reuse`, `item_transform`, `item_visibility`, `item_order` e `studio_undo`. As edições usam o mesmo motor, histórico de desfazer e salvamento local do editor. A lista restrita inclui fontes visuais, câmera macOS (`macos-avcapture`) e entrada de áudio CoreAudio (`coreaudio_input_capture`); consulte `source_types` e `source_options` no Mac em uso. A seleção de dispositivos usa as configurações da fonte e pode solicitar permissão do macOS. `source_reuse` também aceita um microfone existente, preservando o UUID e os controles de áudio compartilhados entre cenas. `scene_items` não devolve configurações privadas de fontes nem chaves de transmissão.

Para adicionar um visualizador, leia em `scene_items` o `sourceUUID` de um item com `audio: true`; use `source_add` com tipo `dante_audio_visualizer` e `settings` contendo `audioSourceUUID`, `style` de 0 a 9, `primary` e `secondary` em RGB inteiro, `sensitivity` de 0,25 a 4 e `layoutWidth`/`layoutHeight`. O componente é apenas visual e não altera o áudio.

As ferramentas de leitura continuam disponíveis durante uma live, mas as edições são recusadas enquanto houver transmissão, gravação, replay ou preparação em andamento. O MCP não inicia/encerra transmissão, não gerencia convidados e não expõe credenciais. Desative o interruptor nas Preferências para fechar imediatamente o socket. O cliente MCP que você configurar recebe poder de editar seu projeto local: conceda acesso somente a clientes de IA em que você confia e confira as alterações no canvas antes de transmitir.

O protocolo implementado usa o ciclo `initialize`/`notifications/initialized` e `tools/list`/`tools/call` da revisão **2025-11-25** do MCP. Clientes que exigem exclusivamente revisões posteriores precisam negociar essa revisão ou usar um adaptador. A compatibilidade foi testada com mensagens JSON-RPC locais; ainda requer validação com os clientes específicos e com o aplicativo empacotado em macOS 14 e Intel físico.
