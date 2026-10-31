# Exercício 8.1: Job paralelo com logs agregados

minikube `cp-bara`, Kubernetes v1.33.1, namespace `store-dev`. Saída completa, com comando e horário: `evidencias.txt`.

| Arquivo | Conteúdo |
|---|---|
| `job-paralelo.yaml` | Job `processa-pedidos`: `completions: 10`, `parallelism: 3`, `backoffLimit: 4`, `ttlSecondsAfterFinished: 600`. Cada Pod imprime o hostname, dorme de 3 a 8 s (`$(( (RANDOM % 6) + 3 ))`) e termina com `LOTE OK <hostname>` |
| `job-indexed.yaml` | Job `processa-particoes`: `completionMode: Indexed`, `completions: 4`. Cada Pod imprime `PARTICAO ${JOB_COMPLETION_INDEX}` |

## Nunca mais de 3 Pods `Running`

Seis amostras de `kubectl get job,pods -l job-name=processa-pedidos` durante a execução, a cada 4 s:

| Horário | COMPLETIONS | Pods `Running` |
|---|---|---|
| 17:10:45 | 0/10 | 3 |
| 17:10:49 | 1/10 | 3 |
| 17:10:54 | 3/10 | 3 |
| 17:10:58 | 5/10 | 1 (+1 `ContainerCreating`) |
| 17:11:02 | 6/10 | 2 |
| 17:11:06 | 8/10 | 1 |

Final: `job.batch/processa-pedidos   Complete   10/10   31s`.

## Logs agregados pelo seletor `job-name`

```
$ kubectl logs -l job-name=processa-pedidos -n store-dev --prefix --tail=1
[pod/processa-pedidos-c7jdq/worker] LOTE OK processa-pedidos-c7jdq
[pod/processa-pedidos-fbgx2/worker] LOTE OK processa-pedidos-fbgx2
... (10 linhas, uma por Pod)
$ kubectl logs -l job-name=processa-pedidos -n store-dev --tail=1 | grep -c 'LOTE OK'
10
```

## Job Indexed: índices 0 a 3, sem repetição

```
pod/processa-particoes-0-q2m7p   Completed   JOB-COMPLETION-INDEX 0
pod/processa-particoes-1-vj9rs   Completed   JOB-COMPLETION-INDEX 1
pod/processa-particoes-2-mfxvz   Completed   JOB-COMPLETION-INDEX 2
pod/processa-particoes-3-qp5t7   Completed   JOB-COMPLETION-INDEX 3

[pod/processa-particoes-0-q2m7p/worker] PARTICAO 0 processada por processa-particoes-0
[pod/processa-particoes-1-vj9rs/worker] PARTICAO 1 processada por processa-particoes-1
[pod/processa-particoes-2-mfxvz/worker] PARTICAO 2 processada por processa-particoes-2
[pod/processa-particoes-3-qp5t7/worker] PARTICAO 3 processada por processa-particoes-3

índices distintos: 0 1 2 3   |   repetidos (uniq -d): 0
```

No modo Indexed, o hostname do Pod também carrega o índice (`processa-particoes-N`), o que permite endereçar cada partição de forma estável.

## Critérios de aceite

- [x] `COMPLETIONS 10/10` com STATUS `Complete`
- [x] Nenhuma amostra mostra mais de 3 Pods em `Running`
- [x] Logs agregados com 10 linhas `LOTE OK`
- [x] Job Indexed com exatamente os índices 0, 1, 2 e 3
