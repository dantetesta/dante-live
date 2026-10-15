# Contribuindo com o Dante Live

O Dante Live está em desenvolvimento ativo. Pessoas que trabalham com produção audiovisual, Swift, C/C++, áudio, vídeo, acessibilidade, testes e documentação são bem-vindas.

## Por onde começar

1. Leia o [README](README.md) e o [guia de build](docs/BUILD.md).
2. Confira as [issues](https://github.com/dantetesta/dante-live/issues) antes de começar. Para uma mudança grande, abra uma proposta descrevendo o problema e o resultado esperado.
3. Crie um fork e uma branch para uma alteração de escopo claro.
4. Inclua a validação que corresponde à mudança. Informe o que não conseguiu testar.
5. Abra um pull request com o problema, a solução, os testes e eventuais limitações.

## Áreas em que precisamos de ajuda

- Editor de cenas: organização das camadas, grupos, seleção múltipla, alinhamento e navegação por teclado.
- Desempenho: profiling do preview, cópias de quadros, uso de CPU/GPU e memória em sessões longas.
- Convidados remotos: convite por link, câmera, microfone e tela como fontes independentes, reconexão e retorno de áudio sem eco.
- Persistência: conexões nomeadas, migrações e recuperação de projetos.
- Compatibilidade: testar dispositivos, GPUs e versões do sistema em hardware real.
- Acessibilidade, tradução e clareza da interface em português.
- Build, documentação, inventário de dependências e preparação de distribuição.

## Cuidados com código audiovisual

- Preserve a instalação e os perfis do OBS Studio. Nunca automatize o encerramento de outro aplicativo para executar um teste.
- Use fontes sintéticas e RTMP local nos testes automáticos; não use chaves ou canais reais em fixtures.
- Respeite ownership, threads e ciclo de vida descritos em `Sources/Bridge/DanteEngine.h`.
- Não bloqueie callbacks de áudio com disco, rede ou trabalho de interface.
- Limite filas e buffers. Trate desconexão, cancelamento e permissões negadas como estados normais.
- Diferencie fonte disponível no catálogo, funcionalidade implementada e funcionalidade validada.
- Melhorias de desempenho exigem medições equivalentes. Trocar linguagem ou reduzir qualidade não comprova otimização.

## Relatando um problema

Inclua versão/commit, sistema, processador/GPU, tipo de fonte e passos para reproduzir. Descreva o comportamento esperado e o observado. Para problemas de desempenho, informe resolução, FPS, encoder, número de fontes e se o modo estúdio estava ativo.

Remova chaves de transmissão, tokens, URLs autenticadas, dados pessoais e conteúdo privado de logs e imagens. Não publique credenciais em issues ou pull requests.

## Licenças e dependências

O projeto usa a GNU GPL versão 2 ou posterior, com créditos e licenças próprios das dependências. As contribuições devem ser compatíveis com esses termos. Preserve os avisos do código reutilizado e documente origem, versão e motivo de cada nova dependência.

O código público ainda não representa uma distribuição binária pronta: assinatura, notarização, fonte correspondente integral das dependências e testes em todos os ambientes-alvo têm pendências. Não apresente um pacote experimental como release estável.
