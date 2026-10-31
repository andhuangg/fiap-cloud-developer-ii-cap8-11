# Checklist de produção (seção 10.14): FIAP Store em `store-prod`

Avaliado sobre o overlay `k8s/overlays/prod`, aplicado no minikube `cp-bara` (evidências em `saidas.txt`).
Legenda: `[x]` atendido · `[ ]` não atendido (com justificativa) · `[-]` não aplicável (com justificativa).

## Imagem e build

- [x] Imagem base mínima, multi-stage: `store-api` em distroless com multi-stage (ex. 10.2); `store-front` em `nginx-unprivileged:1.30-alpine-slim`; `store-worker` em `busybox`.
- [x] `USER` numérico não-root: `USER 65532:65532` na store-api, e o Pod força `runAsUser` em todos os containers.
- [x] Tag imutável, nunca `:latest`: todas as imagens com tag explícita (`1.1`, `1.2`, `1.30-alpine-slim`, `1.36`). Digest seria o ideal; fica como evolução.
- [x] Scan sem CVE CRITICAL corrigível: `make scan` (Trivy `--exit-code 1 --ignore-unfixed`) passa em todas as imagens. Ele **barrou** a `nginx-unprivileged:1.27-alpine` (3 CRITICAL corrigíveis), que foi trocada.
- [ ] SBOM gerado e imagem assinada com Cosign: o SBOM CycloneDX foi gerado (ex. 10.2), mas as imagens deste ambiente local não estão assinadas. A assinatura keyless foi implementada no CI do capítulo 11.
- [x] `.dockerignore` cobrindo `.git`, `.env` e credenciais (ex. 10.2, provado que o `.env` não entra na imagem).
- [-] Registry privado (ECR) com scan on push: o laboratório usa imagens carregadas direto no minikube, e não há conta de nuvem. No capítulo 11 as imagens vão para o GHCR.

## Segurança do workload

- [x] `securityContext` com `runAsNonRoot`, `runAsUser` e `allowPrivilegeEscalation: false`, nos 3 Deployments.
- [x] `readOnlyRootFilesystem: true` com `emptyDir` em `/tmp` (api e front).
- [x] `capabilities.drop: ["ALL"]` e `seccompProfile: RuntimeDefault`.
- [x] PSA: `store-prod` com `enforce: restricted`. `store-dev` com `baseline`, justificado: dev é para depuração, e `warn: restricted` avisa o que quebraria em prod. Teste: `kubectl run psa-teste` em prod foi **rejeitado** com 4 violações.
- [x] `automountServiceAccountToken: false` (nenhum dos apps fala com a API do Kubernetes).
- [x] ServiceAccount dedicada por app (`store-api`, `store-front`, `store-worker`) sem nenhum binding. Modelo de acesso humano de menor privilégio no ex. 9.4, sem `cluster-admin`.
- [x] NetworkPolicy default-deny + allow explícito: `default-deny-all` (Ingress+Egress), DNS, ingress→front, front/worker→api, monitoring→api. Ressalva: o CNI `bridge` do minikube não aplica NetworkPolicy. Em produção, com Calico ou Cilium, as regras passam a valer.
- [ ] Secrets fora do Git com encryption at rest: os apps ainda não usam Secrets e nada sensível está no Git, mas o minikube não tem encryption at rest do etcd configurada. Sealed Secrets foi usado no capítulo 11 (ex. 11.3).
- [x] Sem `hostNetwork`, `hostPID`, `hostPath` ou `privileged`, garantido pelo PSA `restricted`.

## Confiabilidade

- [x] `replicas >= 2` com `topologySpreadConstraints` (3 réplicas por app; spread por `kubernetes.io/hostname`, que vale com multi-node).
- [x] `readinessProbe` (`/ready`) e `livenessProbe` (`/health`) distintas, com liveness mais tolerante (`initialDelaySeconds: 10`, `failureThreshold: 3`).
- [-] `startupProbe`: a store-api sobe em cerca de 1 s (medido no ex. 10.3), bem abaixo dos 20 s que justificariam.
- [x] `preStop` (`sleep 10`, ação nativa, porque o distroless não tem `/bin/sleep`) + `terminationGracePeriodSeconds: 45`. Visto em `saidas.txt`: Pods antigos em `Terminating` durante o rollout.
- [x] Trata SIGTERM, `ENTRYPOINT` exec: store-api em forma exec (1.1), com `lifespan` na 1.2; o worker usa `trap TERM`. Comprovado no ex. 10.3.
- [x] `PodDisruptionBudget` `minAvailable: 2` para api e front (3 réplicas, então `ALLOWED DISRUPTIONS: 1`).
- [x] `maxUnavailable: 0`, `maxSurge: 1` na base.
- [x] HPA de CPU 70%, de 3 a 10 réplicas, com `stabilizationWindowSeconds: 300` no scale down (`cpu: 8%/70%` lido). CPU representa bem a carga de uma API stateless. Para fila, o certo seria KEDA (ex. 8.4).

## Recursos

- [ ] `requests` com base em medição: os valores vieram de `kubectl top` em repouso (cerca de 35m CPU / 34Mi na api), não de teste de carga. Falta um teste de carga ou o VPA em modo recomendação.
- [x] `limits` de memória = request (store-api em prod: 192Mi/192Mi, sem overcommit de memória).
- [x] `limits` de CPU omitidos, de propósito, para evitar throttling (seção 10.10.4).
- [x] `LimitRange` (`limites-padrao`) e `ResourceQuota` (`quota-store-prod`: 2 CPU, 2Gi de request, 30 Pods).
- [x] `priorityClassName: fiap-store-critico` na store-api (value 100000).

## Observabilidade

- [ ] Logs em JSON com `request_id`: o uvicorn loga em texto. Falta o log estruturado e um middleware de `request_id`.
- [-] Agregação de logs fora do cluster: não há backend de logs no laboratório local (seria o CloudWatch ou um Loki).
- [ ] `/metrics` exposto e `ServiceMonitor`: o `ServiceMonitor` foi criado (CRD instalado pelo `make prereqs`), mas a store-api ainda não expõe `/metrics`. Falta `prometheus-fastapi-instrumentator`.
- [-] Dashboard com os 4 sinais dourados: sem Prometheus/Grafana no laboratório.
- [-] Alertas acionáveis e SLO: dependem do item anterior.
- [ ] Tracing com OpenTelemetry: não instrumentado.

## Operação

- [x] Manifestos versionados (Kustomize) e aplicados por GitOps: Kustomize aqui; Argo CD + Git no capítulo 11.
- [-] Runbook para os alertas principais: não há alertas (ver Observabilidade).
- [-] Backup e restauração: os 3 componentes são stateless. O estado da FIAP Store fica no `store-db`, fora deste pacote.
- [x] Plano de upgrade: ver a seção abaixo.
- [ ] Staging equivalente a produção: `store-dev` é deliberadamente diferente (1 réplica, baseline, sem PDB/HPA). Um staging seria um terceiro overlay copiando o de prod.
- [ ] Custos por namespace/label: os labels `ambiente` e `app.kubernetes.io/part-of` permitem rateio, mas nenhuma ferramenta (OpenCost/Kubecost) está instalada.

## Placar

| Status | Itens |
|---|---|
| `[x]` atendido | 26 |
| `[-]` não aplicável, justificado | 7 |
| `[ ]` não atendido, justificado | 8 |
| **Total** | **41** |

**`[x]` + `[-]` = 33/41 = 80,5%** (critério: mínimo 80%). Os 8 não atendidos ficam como próximos passos, quase todos de observabilidade.

## Plano de upgrade (item da seção Operação)

1. **Versões fixadas:** `enforce-version: v1.33` no PSA, tags de imagem explícitas e CRD do ServiceMonitor fixado em `v0.80.1` no Makefile. Nada muda sozinho.
2. **Antes de subir o cluster de 1.33 para 1.34:** rodar `pluto detect-files -d k8s/` (ou `kubent`) para achar APIs removidas, ler as release notes e testar o overlay num cluster descartável (`minikube start --kubernetes-version=v1.34.x`) com `make validate`.
3. **Ordem:** control plane, depois os nodes, um de cada vez. O PDB `minAvailable: 2` garante que o drain nunca derrube a API.
4. **Só depois** atualizar `enforce-version` do PSA para a versão nova, com `warn` primeiro.
5. **Dependências** (imagens base e libs Python) a cada mês, ou quando o `make scan` falhar, sempre passando por dev antes de prod.
