# Exercício 8.4: Processamento de fila com escala a zero (KEDA)

Trilha escolhida: **A (KEDA)**, executada de verdade. minikube `cp-bara`, Kubernetes v1.33.1.

| Arquivo | Conteúdo |
|---|---|
| `keda-scaledjob.yaml` | ScaledJob `store-worker-fila`: trigger `redis`, `listName: pedidos`, `listLength: "5"`, `minReplicaCount: 0`, `maxReplicaCount: 10` |
| `redis.yaml` | Redis `redis:7-alpine` usado como fila |
| `COMPARACAO.md` | Job fixo x KEDA x SQS+Lambda, cerca de 1.200 palavras, cinco eixos com números e recomendação |
| `evidencias/00-instalacao.txt` | `helm install keda` (KEDA 2.21) e Redis |
| `evidencias/01-ciclo-zero-N-zero-rodada1.txt` | primeira rodada |
| `evidencias/02-ciclo-zero-N-zero-rodada2.txt` | segunda rodada, com contagem de pedidos processados e o `describe scaledjob` |

## Ciclo zero → N → zero (rodada 2)

**(a) Fila vazia, zero Pods.** 17:18:58:

```
LLEN pedidos -> 0
kubectl get pods -n store-dev -l app=store-worker -> No resources found in store-dev namespace.
```

**(b) 50 itens inseridos com `redis-cli RPUSH`, e o KEDA cria 10 Jobs.**

```
17:19:03  LLEN pedidos: 50   10 Pods ContainerCreating
17:19:08  LLEN pedidos: 30   10 Pods Running
17:19:14  LLEN pedidos: 10   10 Pods Running
```

**(c) Fila esvaziada, volta a zero.**

```
17:19:19 LLEN=0 pods=10
17:19:25 LLEN=0 pods=0
kubectl get pods -n store-dev -l app=store-worker -> No resources found in store-dev namespace.
```

**Conferência de que nada se perdeu:** `LLEN processados` = **50**. Foram exatamente 5 pedidos por Job (10 Jobs × 5), igual ao `listLength`.

**`kubectl describe scaledjob store-worker-fila`** (eventos):

```
Normal  KEDAJobsCreated     scale-handler  Created 10 jobs
Normal  ScaledJobActive     scale-handler  Scaling is performed because triggers are active
Normal  ScaledJobInactive   scale-handler  Scaling is not performed because triggers are not active
```

## Observações

- O KEDA 2.21 avisa no `helm install` que é testado a partir do Kubernetes 1.34. Mesmo assim funcionou no 1.33.
- Achado registrado no `COMPARACAO.md`: o worker usa `LPOP`, que retira o item **antes** de processar. Se o Pod morrer no meio, o pedido se perde. Em produção, o certo seria `LMOVE` para uma lista de processamento, ou usar o SQS.

## Critérios de aceite

- [x] Três capturas de `kubectl get pods` provando o ciclo zero → N → zero
- [x] `COMPARACAO.md` cobre os cinco eixos (pico de 10.000, cold start, limite de tempo, custo com números, falhas), com recomendação justificada para a Black Friday
