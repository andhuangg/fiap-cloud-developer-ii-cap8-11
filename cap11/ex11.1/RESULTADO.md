# Exercício 11.1: Argo CD + primeira Application com sync automático

| Item | Valor |
|---|---|
| Repositório (config repo) | https://github.com/andhuangg/fiap-store-config |
| Repositório da aplicação (imagens) | https://github.com/andhuangg/fiap-store-api, que publica `ghcr.io/andhuangg/fiap-store-api` |
| Cluster | minikube `cp-bara`, Kubernetes v1.33.1 |
| Argo CD | v2.13.9 (servidor e CLI) |

Saída completa, com comando e horário: `saidas.txt`. Print da UI: `print-grafo-fiap-store-dev.png`.

## Passos

1. Argo CD v2.13.9 instalado no namespace `argocd` (manifesto oficial `install.yaml`).
2. Senha inicial recuperada do `argocd-initial-admin-secret`, trocada com `argocd account update-password`, e o secret **apagado** (`NotFound` comprovado). A senha antiga passou a ser rejeitada (`Invalid username or password`).
3. Config repo público com:
   - `base/`: Deployment + Service da `store-api` com o securityContext completo do capítulo 10 (`runAsNonRoot`, UID 65532, `readOnlyRootFilesystem`, `drop ALL`, `seccompProfile`);
   - `overlays/dev/`: namespace `store-dev`, 2 réplicas, tag `1.0`.

   Validado com `kubectl kustomize overlays/dev` **antes** do commit.
4. Application `fiap-store-dev` (`apps/store-dev.yaml`):
   - `syncPolicy.automated` com `prune: true` e `selfHeal: true`;
   - `CreateNamespace=true`;
   - finalizer `resources-finalizer.argocd.argoproj.io`;
   - extra: `managedNamespaceMetadata` com o PSA `restricted` no namespace criado.
5. Commit trocando as réplicas de 2 para 4. Depois dele, nenhum comando de escrita no cluster: só `get` e `argocd app get`.

## Evidências

**Application Synced/Healthy, depois do commit:**

```
Sync Policy:        Automated (Prune)          # spec: {"automated":{"prune":true,"selfHeal":true}, ...}
Sync Status:        Synced to main (42151e6)
Health Status:      Healthy
```

**Pods antes do commit (2):**

```
store-api-7b88c88757-q4dfs   1/1   Running   10.244.0.172
store-api-7b88c88757-zdv9l   1/1   Running   10.244.0.173
```

**Pods depois do commit (4), sem nenhum `kubectl apply`/`scale`:**

```
store-api-7b88c88757-q4dfs   1/1   Running   4m11s
store-api-7b88c88757-zdv9l   1/1   Running   4m11s
store-api-7b88c88757-4qcf8   1/1   Running   7s
store-api-7b88c88757-tktjt   1/1   Running   7s
```

**Horário do commit x criação dos Pods novos:**

| Evento | Horário (UTC) |
|---|---|
| commit `42151e6` "dev: store-api de 2 para 4 replicas" | 21:16:25 (18:16:25 −03) |
| Pods `4qcf8` e `tktjt` criados (`creationTimestamp`) | 21:19:57 |
| Diferença | **3 min 32 s**, o intervalo de polling padrão do Argo CD (180 s) + jitter |

Durante a espera, o acompanhamento a cada 10 s mostra a Application presa na revisão antiga (`850b556`) até as 18:19:53 e, às 18:20:04, `42151e6 Synced/Healthy` com 4 Pods.

**`argocd app history fiap-store-dev`, com 2 revisões distintas:**

```
ID  DATE                           REVISION
0   2026-10-31 18:07:20 -0300 -03  main (850b556)
1   2026-10-31 18:19:57 -0300 -03  main (42151e6)
```

## Problemas encontrados e resolvidos no caminho

- **CLI v3.5.1 contra servidor v2.13.9:** o login via gRPC falhava (`context deadline exceeded`). Resolvido com o CLI na mesma versão do servidor (v2.13.9).
- **Push recusado** (o Keychain do macOS mandou a credencial de outra conta): sem conteúdo no repo, a Application ficou `Unknown` com `remote repository is empty`. Isso é exatamente o sintoma descrito na dica do exercício, só que com causa diferente do `repoURL`.
- **`ErrImagePull: no matching manifest for linux/arm64/v8`:** o CI publicava só `amd64` e o minikube roda em Apple Silicon. O CI passou a publicar `linux/amd64` + `linux/arm64`.

## Critérios de aceite

- [x] Application em `Sync Status: Synced` e `Health Status: Healthy`
- [x] 4 Pods `Running` sem nenhum `kubectl apply`/`scale` após a criação da Application
- [x] `argocd app history fiap-store-dev` lista 2 revisões distintas (`850b556`, `42151e6`)
- [x] Print do grafo de recursos na UI (`print-grafo-fiap-store-dev.png`): Application → Service/Deployment → EndpointSlice/ReplicaSet → 4 Pods
