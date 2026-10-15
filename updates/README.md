# Atualizações do Dante Live

O aplicativo consulta `appcast.xml`, assinado com Ed25519. Cada item aponta para o DMG imutável da respectiva [GitHub Release](https://github.com/dantetesta/dante-live/releases).

- `releases/<versão>.json`: versão, build, URL, tamanho, SHA-256, assinatura e changelog.
- `changelogs/<versão>.md`: novidades mostradas também no atualizador.
- `appcast.xml`: catálogo assinado, gerado somente após publicar e verificar os arquivos.

Os DMGs ficam em Releases para evitar arquivos binários grandes no histórico Git. Não editar o XML manualmente: qualquer alteração invalida sua assinatura. O fluxo de publicação mantém os registros anteriores e rejeita versões/builds repetidos.

Consulte [UPDATES.md](../docs/UPDATES.md) para uso, segurança e manutenção. A versão 0.1.7 inaugura este catálogo; versões anteriores continuam disponíveis em Releases, mas não têm atualizador interno.
