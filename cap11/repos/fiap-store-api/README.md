# fiap-store-api

App repo da `store-api` (FIAP Store, Cloud Developer II). Código, testes e Dockerfile.

O deploy **não** acontece aqui: o CI (`.github/workflows/ci.yaml`) testa, constrói, escaneia com Trivy, publica a imagem no GHCR e abre um pull request no config repo [`fiap-store-config`](https://github.com/andhuangg/fiap-store-config) trocando a tag em `overlays/dev`. Quem aplica no cluster é o Argo CD (modelo pull do GitOps).

- push na `main`: imagem `ghcr.io/andhuangg/fiap-store-api:<run_number>` + PR de bump em `overlays/dev`
- tag `vX.Y`: imagem `ghcr.io/andhuangg/fiap-store-api:X.Y` (release)
