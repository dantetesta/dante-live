# Publicar uma versão para Mac

Publicar somente a partir do checkout público limpo, branch `main`. Aumente `CFBundleShortVersionString` e `CFBundleVersion`, atualize os avisos/estado, revise e envie o código ao GitHub antes de iniciar. Uma versão publicada nunca deve ter seus arquivos sobrescritos.

```sh
bash scripts/release.sh /caminho/absoluto/notas-da-versao.txt
```

O comando compila Universal 2 em um diretório da versão, executa `test-app.sh`, audita as arquiteturas/dependências/assinatura, gera e verifica o DMG, verifica e empacota as fontes fixadas, e publica uma **pré-release experimental**. Requer macOS, ferramentas de build, GitHub CLI autenticado e permissão de escrita no repositório.

A publicação começa como rascunho. Os três assets (DMG, fontes e SHA256SUMS) precisam ter hashes remotos iguais aos arquivos locais antes de tornar a release pública. Em falha, inspecione o rascunho; não substitua uma release pública. O catálogo assinado, changelog e README são enviados após publicar. Se esse push falhar, a release continua acessível: revise e envie somente o commit pendente. Não recrie a release.

O botão usa a URL versionada do DMG, pois o endpoint GitHub `latest` não seleciona pré-releases. O fluxo atualiza essa URL a cada publicação bem-sucedida. `scripts/package.sh` permanece útil para builds locais sem publicar acidentalmente artefatos de desenvolvimento.

Os instaladores atuais têm assinatura ad hoc, sem notarização. Não anunciar estabilidade, execução física Intel/macOS 14 ou equivalência completa ao OBS sem evidência. Não iniciar captura ou transmissão pública como parte do build.

Para validar um artefato preparado anteriormente, use `scripts/publish-release.py --dmg ... --source ... --notes ...`; o ZIP deve referenciar exatamente o commit público corrente. A versão 0.1.3 foi verificada também por montagem somente leitura e comparação integral do conteúdo com o aplicativo compilado.

## Assinaturas de atualização (0.1.7+)

A chave Ed25519 de produção precisa estar no Keychain sob a conta `com.dantetesta.DanteLive.updates` e corresponder ao `SUPublicEDKey` empacotado. O script falha antes de publicar se não corresponder. Nunca gerar outra chave para contornar essa falha. Se o SDK estiver em outro checkout, definir `DANTE_SPARKLE_TOOLS` para o diretório `bin` da versão fixada.

`packaging/update-feed.py` inspeciona o DMG montado, verifica Universal 2, versão e assinatura, assina o arquivo e prepara `updates/releases`, `updates/changelogs` e `updates/appcast.xml`. O publicador envia esses arquivos somente depois de conferir os hashes dos assets remotos. Os builds precisam ser inteiros crescentes; os anteriores permanecem no catálogo. Nunca editar diretamente o XML assinado. Ver [UPDATES.md](UPDATES.md).
