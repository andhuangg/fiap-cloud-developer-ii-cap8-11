# fiap-store-config

Config repo GitOps da FIAP Store (Cloud Developer II, capítulo 11). É a **fonte da verdade** do que roda no cluster: o Argo CD observa este repositório e reconcilia o cluster com ele.

- `base/`: manifestos comuns (store-api com o securityContext do capítulo 10)
- `overlays/dev`, `overlays/prod`: diferenças por ambiente (Kustomize)
- `apps/`: objetos `Application` / `AppProject` do Argo CD

Mudança no cluster = commit (ou PR) aqui. Nada de `kubectl apply` manual.
