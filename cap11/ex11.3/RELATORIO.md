# Exercício 11.3: Plantão GitOps, Application `OutOfSync` e `Degraded`

Config repo: https://github.com/andhuangg/fiap-store-config (todas as correções foram feitas por commit). Saídas completas, com comando e horário:

| Arquivo | Cenário |
|---|---|
| `A-drift.txt` | A |
| `B-synced-degraded.txt` | B |
| `C-sealed-secrets.txt` | C |
| `D-bonus-rbac.txt` | D |

SealedSecret commitado: `sealedsecret-store-db-dev.yaml`.

---

## Cenário A: drift manual

**Sintoma.** Alguém fez `kubectl scale --replicas=1` e `kubectl set image ... nginx:1.27` direto no cluster.

**Diagnóstico.** `argocd app diff fiap-store-dev --refresh`, rodado imediatamente após o drift:

```
===== apps/Deployment store-dev/store-api ======
201c201
<   replicas: 1
---
>   replicas: 4
222c222
<         image: nginx:1.27
---
>         image: ghcr.io/andhuangg/fiap-store-api:1.1
```

**Com `selfHeal: true`.** O Argo desfez as duas alterações em cerca de 2 s:

```
18:31:46 spec.replicas=1 image=nginx:1.27
18:31:48 spec.replicas=4 image=ghcr.io/andhuangg/fiap-store-api:1.1
```

Logs do `argocd-application-controller`:

```
21:31:45Z msg="Initiated automated sync to '3db36453...'" application=fiap-store-dev
21:31:45Z msg="Updated sync status: Synced -> OutOfSync"
```

Eventos: `Partial sync operation ... succeeded` e `OutOfSync -> Synced`. Estado final: `Synced/Healthy`, 4/4 em `:1.1`.

**Com o sync automático desligado** (`argocd app set fiap-store-dev --sync-policy none`), o mesmo drift **permanece**. Depois de 60 s:

```
Sync Policy:   Manual
Sync Status:   OutOfSync from main (3db3645)
apps  Deployment  store-dev  store-api  OutOfSync  Progressing
store-api   1/1   ...   nginx:1.27
```

O Argo **detecta** o drift (OutOfSync) mas não age, porque sem política automática a decisão de sincronizar é humana.

Observação: o Pod `nginx:1.27` foi admitido pelo PSA (o securityContext do Pod continuou conforme), mas não fica pronto. Com `maxUnavailable: 0`, um Pod `1.1` continuou servindo.

**Causa raiz.** Mudança feita direto no cluster, fora do Git.

**Correção pelo Git.** Reapliquei a Application exatamente como está versionada em `apps/store-dev.yaml` (com `automated.prune` e `selfHeal`). O Argo voltou a `Automated (Prune)`, desfez o drift sozinho e terminou em `Synced/Healthy`, 4/4 em `:1.1`.

**Diferença de comportamento.** `selfHeal` faz o Git ser a verdade **contínua**: qualquer desvio é revertido em segundos. Sem ele, o Git é a verdade **declarada**, mas o cluster pode divergir até alguém sincronizar. É útil numa emergência, mas o desvio fica visível como OutOfSync, nunca escondido.

---

## Cenário B: `Synced` + `Degraded`

**Sintoma.** Commit `667c5af` com `newTag: 9.9-inexistente`. A Application ficou:

```
Sync Status:        Synced to main (667c5af)
Health Status:      Degraded
apps  Deployment  store-dev  store-api  Synced  Degraded  deployment.apps/store-api configured
```

**Diagnóstico.**

`kubectl describe pod` do Pod novo:

```
Failed to pull image "ghcr.io/andhuangg/fiap-store-api:9.9-inexistente": Error response from daemon: manifest unknown
Error: ImagePullBackOff
```

Condição do Deployment:

```
Progressing=False ProgressDeadlineExceeded: ReplicaSet "store-api-657bc6cd57" has timed out progressing.
```

Controller do Argo:

```
21:36:07Z msg="Updated health status: Progressing -> Degraded" application=fiap-store-dev
```

(O `progressDeadlineSeconds: 120` foi commitado na base antes do teste. Com o padrão de 600 s, o `Degraded` levaria 10 min.) Os 4 Pods `1.1` continuaram `Running` durante todo o incidente, graças ao `maxUnavailable: 0`.

**Por que não é bug do Argo.**
- **Sync status** responde: "o cluster é igual ao Git?". E é: o Argo aplicou exatamente o que o commit pediu (tag `9.9-inexistente`).
- **Health status** responde: "os recursos aplicados estão funcionando?". E não estão: a imagem não existe e o rollout estourou o prazo.

São duas perguntas independentes. Synced + Degraded significa: o Git pediu uma coisa quebrada, e o Argo obedeceu fielmente. O erro está no commit, e o lugar de corrigir é o Git.

**Causa raiz.** Tag de imagem inexistente no `overlays/dev`.

**Correção.** `git revert` gerou o commit `1054fe6`, e o resultado foi `Synced to main (1054fe6)`, `Healthy`, 4/4 em `:1.1`.

---

## Cenário C: sync falhando por dependência ausente (Secret)

**Sintoma.** Commit `b6a09d7` adicionou à `base/` o Deployment `store-relatorio`, que lê `DB_PASSWORD` via `secretKeyRef` do Secret `store-db-credentials`. O Secret não existe no cluster e, corretamente, não está no Git.

```
store-relatorio-6c75bf98db-2wpbm   0/1   CreateContainerConfigError
Warning  Failed  kubelet  Error: secret "store-db-credentials" not found
$ kubectl get secret store-db-credentials -n store-dev
Error from server (NotFound): secrets "store-db-credentials" not found
```

A Application fica `Synced/Progressing`: o Deployment foi aplicado, mas não fica saudável.

**Causa raiz.** Dependência (Secret) ausente. Não dá para commitar um Secret comum, porque base64 não é criptografia.

**Correção.**
1. Instalado o controller do Sealed Secrets v0.41.2 em `kube-system` (mesma versão do `kubeseal`).
2. Gerado um `SealedSecret` por namespace, porque a cifragem é atrelada a namespace + nome:
   ```
   kubectl create secret generic store-db-credentials -n store-<ns> --from-literal=DB_PASSWORD="$SENHA" --dry-run=client -o yaml \
     | kubeseal --format yaml --controller-namespace kube-system --controller-name sealed-secrets-controller
   ```
3. Commitados `overlays/dev/sealedsecret-store-db.yaml` e `overlays/prod/sealedsecret-store-db.yaml` (commit `0972205`). O Argo criou os `SealedSecret`, e o controller os decifrou para `Secret`.

**Evidência.**

```
sealedsecret.bitnami.com/store-db-credentials   10s
secret/store-db-credentials   Opaque   1   10s        ownerReference: SealedSecret/store-db-credentials
store-relatorio-6c75bf98db-2wpbm   1/1   Running
log: conectando no store-db com senha de 22 caracteres
Sync Status: Synced to main (0972205)   Health Status: Healthy
bitnami.com  SealedSecret  store-dev  store-db-credentials  Synced  Healthy
```

**Prova de que o arquivo commitado não revela a senha.** A senha de laboratório usada foi `fiap-db-S3nh4-lab-2026`:

```
git grep -i 'fiap-db-S3nh4-lab-2026' $(git rev-list --all)   -> 0   (nenhum commit, em todo o histórico)
grep -ri 'fiap-db-S3nh4-lab-2026' .                         -> 0
grep -ri '<senha em base64>' .                               -> 0   (nem codificada)
```

O arquivo só contém `encryptedData.DB_PASSWORD: AgB0XBKK...`, cifrado com a chave pública do controller. Só o controller, com a chave privada que fica no cluster, decifra.

---

## Cenário D (bônus): falha por RBAC do AppProject

AppProject `fiap-store-sem-ns` com `clusterResourceWhitelist: []` e uma Application com `CreateNamespace=true`:

```
Sync Status:  OutOfSync     Health Status: Missing
Namespace  store-bonus  SyncFailed  resource :Namespace is not permitted in project fiap-store-sem-ns
operationState: one or more synchronization tasks are not valid. Retrying attempt #2
```

O `CreateNamespace=true` faz o Argo criar um objeto `Namespace`, que é de escopo de cluster e precisa estar no `clusterResourceWhitelist` do projeto. O namespace não foi criado (`NotFound`). Por isso o AppProject `fiap-store` do ex. 11.2 permite **exatamente** `Namespace` e nada mais. Os objetos de teste foram removidos.

---

## Critérios de aceite

- [x] Os três cenários principais foram reproduzidos e corrigidos, terminando em `Synced/Healthy` nos três
- [x] Cenário B: sync compara Git x cluster e health avalia o funcionamento dos recursos
- [x] O SealedSecret no repositório não revela a senha (`grep -i` na senha original retorna vazio, em todo o histórico)
- [x] Bônus D reproduzido com a mensagem de erro
