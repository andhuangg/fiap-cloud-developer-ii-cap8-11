# Exercício 11.4: App-of-Apps + CI que atualiza a tag

Repos: https://github.com/andhuangg/fiap-store-config (config) e https://github.com/andhuangg/fiap-store-api (app + CI).
PR aberto pelo CI: https://github.com/andhuangg/fiap-store-config/pull/2

## Parte 1: App-of-Apps

**Por que App-of-Apps (e não ApplicationSet):** cada Application filha tem necessidades diferentes:
- Kyverno vem de chart Helm, Knative de URL de release, a app de Kustomize e o serverless de Knative;
- cada uma tem `ignoreDifferences` e projeto próprios.

Escrever cada filha como YAML explícito em `apps/` deixa isso legível e revisável por PR. O ApplicationSet compensa quando há muitos ambientes idênticos, o que não é o caso de 1 dev, 1 prod e 1 serverless.

Arquivos: `fiap-store-root.yaml` (raiz) e `project.yaml` (AppProject `fiap-store`). A árvore completa do config repo está em `03-estado-final.txt`.

Ordem por sync-wave:

| Onda | O que sobe |
|---|---|
| -3 | AppProjects `fiap-store` e `plataforma` |
| -2 | Kyverno (Helm 3.9.2) e Knative 1.21 + Kourier |
| -1 | namespaces (PSA) + policies Kyverno |
| 0 | `fiap-store-dev` e `fiap-store-prod` (store-api, store-front, store-worker, store-relatorio + hook PreSync) |
| 1 | `fiap-store-serverless` |

Para as ondas esperarem a saúde das filhas, o `argocd-cm` recebeu o health check de `Application` (`root/argocd-cm-health-application.yaml`, configuração da instalação do Argo).

**Um único `kubectl apply`** (`02-reconstrucao-limpa.txt`): teardown completo, depois `kubectl apply -f root/fiap-store-root.yaml`. Em 220 s, 7 Applications ficaram `Synced/Healthy`, criadas na ordem das ondas (22:24:33 onda -2, 22:26:50 onda -1, 22:26:53 onda 0, 22:27:46 onda 1). Print: `print-argocd-apps.png`.

**Ambientes distintos** (`03-estado-final.txt`):

| | dev | prod |
|---|---|---|
| store-api / front / worker | 2 / 1 / 1 réplicas | 4 / 2 / 2 réplicas |
| `APP_ENV` | `dev` | `prod` |
| PDB | não | sim |
| Imagem da store-api (após o PR do CI) | `:6` | `:1.1` |

**Hook PreSync** `valida-store-db`: `PreSync Job/valida-store-db hookPhase=Succeeded` nos dois ambientes.

**Kyverno barrando** (`03-estado-final.txt`): Pod com `:latest` é negado por `proibir-tag-latest`, e Pod sem limits é negado por `exigir-recursos`.

## Parte 2: CI que promove (`ci.yaml`, `04-ci-pr-automatico.txt`)

Push na `main` (`feat: endpoint /categorias`) disparou o run 41245855115 com três jobs:
1. **testes:** pytest.
2. **imagem:** build, scan Trivy (`--exit-code 1 --severity CRITICAL --ignore-unfixed`) **antes** do push, push multi-arch para `ghcr.io/andhuangg/fiap-store-api:6` (`run_number`) e assinatura Cosign keyless (verificada com `cosign verify`).
3. **promover-dev:** clone do config repo, `kustomize edit set image` e PR #2 aberto **sem intervenção manual** (diff de 1 linha: `newTag: "1.1"` para `"6"`).

Após o merge, o Argo levou `store-dev` para `:6` sem nenhum comando no cluster: `/categorias` responde em dev e dá 404 em prod (1.1).

O workflow **não tem KUBECONFIG, kubectl nem credencial de cluster**: o único secret é o `CONFIG_REPO_TOKEN`, que dá acesso ao Git.

## Componente serverless

- Manifesto: `store-api-knative.yaml` (`min-scale: "0"`, `max-scale: "20"`), gerenciado pela Application `fiap-store-serverless`.
- Evidências (`05-serverless.txt`): 0 Pods; uma requisição com HTTP 200 em 5,5 s (cold start) sobe 1 Pod; depois volta a 0. O Argo permanece `Synced/Healthy` o tempo todo.
- Análise: `ANALISE-SERVERLESS.md`.

## Problemas resolvidos no caminho

- **Knative 1.24 exige Kubernetes ≥ 1.35:** troquei pela linha 1.21, a última que aceita 1.33.
- **Service do Kourier `LoadBalancer` fica `Progressing` no minikube:** troquei para `NodePort`.
- **Kyverno `OutOfSync`:** o chart renderiza `labels`/`annotations` vazios nos CRDs (resolvido com `ignoreDifferences`) e deixa um Job de migração sem delete-policy (desligado nos values).
- **Webhook do Knative recusa `securityContext` no nível do Pod:** movi os controles para o nível do container.

## Critérios de aceite

- [x] Um único `kubectl apply -f` resultou em 7 Applications (mínimo 4) `Synced/Healthy`
- [x] Dev e prod com configurações comprovadamente distintas
- [x] PR de bump criado pelo CI sem intervenção manual
- [x] Workflow sem credencial de cluster
- [x] Análise serverless respondendo aos três pontos: o Argo compara `spec` (intenção), não a contagem de Pods
