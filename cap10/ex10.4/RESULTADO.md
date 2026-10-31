# Exercício 10.4: Checklist de produção + empacotamento (Kustomize)

Opção escolhida: **Kustomize**, com `k8s/base` e `k8s/overlays/{dev,prod}`.

| Entregável | Onde |
|---|---|
| Árvore de diretórios (`tree`) | `saidas.txt` (início) |
| Saída de `kubectl kustomize k8s/overlays/prod` | `render-prod.yaml` (e `render-dev.yaml`) |
| `kubectl get all,pdb,hpa,netpol,quota -n store-prod` e `-n store-dev` | `saidas.txt` |
| `CHECKLIST.md` preenchido | `CHECKLIST.md` (33/41 = 80,5% entre `[x]` e `[-]`) |
| `Makefile` | `Makefile` (`deploy-dev`, `deploy-prod`, `scan`, `diff`, `destroy` + `prereqs`, `validate`, `render`) |
| Análise serverless | `ANALISE-SERVERLESS.md` (+ extra `extra-knative/store-api-knative.yaml`) |

## Diferenças entre os ambientes

| | dev (`store-dev`) | prod (`store-prod`) |
|---|---|---|
| Réplicas (api/front/worker) | 1 / 1 / 1 | 3 / 3 / 3 (HPA da api: 3 a 10) |
| Imagem da store-api | `store-api:1.2` (candidata) | `store-api:1.1` (escaneada e aprovada) |
| `APP_ENV` | `dev` (ConfigMap gerado) | `prod` |
| PSA | `baseline` (+ `warn: restricted`) | `restricted` (enforce/audit/warn) |
| Recursos | pequenos (api 25m/48Mi) | maiores (api 100m/192Mi, limit = request), PriorityClass |
| PDB / HPA / preStop+grace | não | sim / sim / sim (10 s, 45 s) |
| NetworkPolicy, LimitRange, ResourceQuota, ServiceMonitor | não | sim |

Evidência (`saidas.txt`):

```
$ kubectl get deploy -n store-dev -o wide
store-api      1/1   ...   store-api:1.2
store-front    1/1   ...   nginxinc/nginx-unprivileged:1.30-alpine-slim
store-worker   1/1   ...   busybox:1.36
$ kubectl get deploy -n store-prod -o wide
store-api      3/3   ...   store-api:1.1
store-front    3/3   ...   nginxinc/nginx-unprivileged:1.30-alpine-slim
store-worker   3/3   ...   busybox:1.36

$ kubectl exec deploy/store-worker -- printenv APP_ENV  ->  dev  /  prod
```

## Critérios de aceite

- [x] **Um único comando sobe o ambiente inteiro:** `make deploy-prod` (CRD do ServiceMonitor + `kubectl apply -k` + `rollout status`) e `make deploy-dev`.
- [x] **Os dois namespaces coexistem com configurações distintas:** réplicas (1 contra 3) e tag (`1.2` contra `1.1`).
- [x] **Nada em `store-prod` viola o PSA `restricted`:** os 9 Pods estão `Running` sob `enforce: restricted`, e um Pod comum (`kubectl run psa-teste`) é rejeitado com 4 violações.
- [x] **Pelo menos 80% do checklist em `[x]` ou `[-]`:** 80,5%.
- [x] **Análise serverless:** responsabilidade transferida (SO e runtime: imagem base) e retida (dependências da aplicação).

## O que aconteceu no caminho

- O `make scan` **barrou** a `nginx-unprivileged:1.27-alpine` (3 CVEs CRITICAL corrigíveis). A `1.28-alpine` e a `1.29-alpine` também tinham. A `1.30-alpine-slim` passou limpa e foi adotada.
- O primeiro `make validate` falhou porque o dry-run no servidor não cria namespaces. O alvo passou a aplicar só os `namespace.yaml` antes do dry-run.
- O `make scan` também não pegava a imagem do nginx, porque no YAML renderizado ela aparece como `- image:`. O padrão do `grep` foi corrigido.
- NetworkPolicies criadas e válidas, mas o CNI `bridge` do minikube não as aplica (anotado no checklist).
