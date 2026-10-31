# Exercício 10.3: Aplicação matando conexões no rolling update

## Arquivos

- **YAML quebrado:** `manifestos/0-quebrado.yaml`
- **YAML final corrigido:** `manifestos/e-final-lifespan.yaml`
- **Etapas intermediárias:** `manifestos/a-*.yaml` até `d-*.yaml`
- **Imagens:** `app/Dockerfile.shell` (ENTRYPOINT em shell form), `app/Dockerfile.exec` (forma exec) e `app/Dockerfile.lifespan` (exec + `main_lifespan.py`)
- **Gerador de carga e medição:** `mede-rollout.sh` (uma etapa) e `roda-tudo.sh` (as 6 etapas em sequência)
- **Evidências:** `evidencias/carga-<etapa>.log` (uma linha OK/FALHA por requisição), `evidencias/resumo.txt`, `evidencias/pid1.txt` e `evidencias/describe-pod-terminating.txt`

## Gerador de carga

Pod `busybox` no mesmo namespace, chamando o Service em laço contínuo:

```sh
while [ ! -f /tmp/parar ]; do
  if wget -q -O /dev/null -T 2 http://store-api/produtos; then echo "$(date +%T) OK"; else echo "$(date +%T) FALHA"; fi
done
```

Para cada etapa:
1. Aplica o manifesto e espera estabilizar.
2. Liga a carga e, 5 s depois, dispara `kubectl set image` para a tag nova.
3. Espera o rollout terminar **e** o último Pod antigo sair de `Terminating`.
4. Desliga a carga e conta as linhas OK e FALHA.

## Resultado: correção aplicada × requisições falhadas

3 réplicas, minikube de 1 node, `kubectl set image` para a tag `-b`. Fonte: `evidencias/resumo.txt`.

| Etapa | Correção acumulada | Requisições | Falhas | **Falhas em 100** | Último Pod antigo sumiu após |
|---|---|---|---|---|---|
| 0 | quebrado: shell form, sem readiness, sem preStop, grace 5 s, `maxUnavailable: 1` | 11.232 | 333 | **2,96** | 8 s |
| a | + `readinessProbe` em `/ready` | 12.196 | 0 | **0,00** | 8 s |
| b | + `preStop sleep 10` e `terminationGracePeriodSeconds: 45` | 40.352 | 0 | **0,00** | 49 s |
| c | + `ENTRYPOINT` em forma exec | 29.327 | 0 | **0,00** | 32 s |
| d | + `maxUnavailable: 0`, `maxSurge: 1` | 20.312 | 0 | **0,00** | 19 s |
| e | + `lifespan` do FastAPI (`/ready` em 503 no shutdown) | 23.658 | 0 | **0,00** | 23 s |

**Versão final:** 23.658 requisições consecutivas sem nenhuma falha durante um rollout completo. As falhas da etapa 0 aconteceram em rajada entre 20:40:00 e 20:40:02 (103 + 202 + 28): Pods novos recebendo tráfego antes de o uvicorn abrir a porta, ao mesmo tempo em que os antigos morriam.

**Por que (a) a (e) já mostram zero falhas.** Num minikube de **um node**, o endpoints controller e o kube-proxy que reprograma o iptables estão na mesma máquina, e cada `wget` abre uma conexão nova (sem keep-alive). A janela da corrida descrita abaixo cai para milissegundos. Neste ambiente, a readinessProbe sozinha eliminou as falhas. As correções (b) a (e) protegem contra a parte da corrida que só aparece com vários nodes, load balancer externo (ALB com deregistration delay) e conexões persistentes. O efeito delas ficou visível nas medições abaixo.

## O que as etapas (b) a (e) mudaram, medido

**Shell form engole o SIGTERM** (`evidencias/pid1.txt`):

```
kubectl exec pid1-shell-a -- cat /proc/1/cmdline  ->  /bin/sh -c sh -c "uvicorn main:app ..."
kubectl exec pid1-exec-a  -- cat /proc/1/cmdline  ->  /opt/venv/bin/python /opt/venv/bin/uvicorn main:app ...
kubectl delete pod pid1-shell-a (grace 20s) levou 20s   <- só morreu no SIGKILL
kubectl delete pod pid1-exec-a  (grace 20s) levou 1s    <- tratou o SIGTERM
```

(A imagem `python:3.12-slim` não tem `ps`, por isso o PID 1 foi lido em `/proc/1/cmdline`, que é equivalente.)

Na tabela, isso aparece na etapa (b): com shell form, o último Pod antigo levou **49 s** para sumir (10 s de preStop + SIGTERM ignorado + SIGKILL ao fim dos 45 s de grace). Na etapa (c), com forma exec, caiu para 32 s. Na etapa (e), o log mostra o shutdown gracioso:

```
SIGTERM recebido: /ready agora responde 503, drenando...
shutdown concluido
INFO:     Application shutdown complete.
```

## Pod em `Terminating` mostrando o preStop

Recorte de `evidencias/describe-pod-terminating.txt`, capturado 6 s após o `set image` da etapa (e):

```
Name:                      store-api-556c9dff96-bk2th
Status:                    Terminating (lasts <invalid>)
Termination Grace Period:  45s
    State:          Running
    Ready:          True
Events:
  Normal  Killing    4s    kubelet            Stopping container store-api

$ kubectl get pod store-api-556c9dff96-bk2th -o jsonpath='{.spec.containers[0].lifecycle}'
{"preStop":{"exec":{"command":["sleep","10"]}}}
terminationGracePeriodSeconds=45
deletionTimestamp=2026-10-31T20:44:57Z
```

O container segue `Running` porque o `preStop` (`sleep 10`) ainda está executando. O SIGTERM só vem depois dele. O `kubectl describe` não imprime os hooks, por isso o `preStop` foi mostrado via jsonpath. O `<invalid>` aparece porque o `deletionTimestamp` fica no futuro (agora + grace).

## Por que os Endpoints e o SIGTERM correm em paralelo

Quando um Pod é marcado para remoção (rolling update ou `kubectl delete`), o API server só grava o `deletionTimestamp`. A partir daí, **dois controladores independentes** reagem ao mesmo evento, sem nenhuma coordenação entre si:

- **(A) Caminho da rede:** o endpoints controller tira o Pod do EndpointSlice. Em seguida, o kube-proxy de **cada node** (e o load balancer externo, se houver) recebe a mudança pelo seu próprio watch e reescreve as regras de iptables/IPVS, cada um no seu tempo.
- **(B) Caminho do processo:** o kubelet do node onde o Pod roda executa o `preStop` e manda SIGTERM ao PID 1.

O Kubernetes não espera (A) terminar antes de iniciar (B). Se a aplicação morre no instante do SIGTERM, qualquer node cujo iptables ainda não foi atualizado continua mandando conexões para um IP que não responde mais. O resultado é `connection refused` ou `reset`.

As correções atacam isso por lados diferentes:

| Correção | O que resolve |
|---|---|
| readinessProbe | o Pod novo só entra no Service quando responde |
| preStop + grace | atrasa o SIGTERM o suficiente para (A) propagar |
| forma exec | o SIGTERM chega de fato ao uvicorn |
| `maxUnavailable: 0` | nunca há menos réplicas prontas que o desejado |
| `lifespan` | a aplicação sinaliza 503 e drena o que está em voo antes de sair |

## Rodada 1 (descartada)

A primeira medição parava a carga cedo demais (logo após o `rollout status`, com Pods antigos ainda em `Terminating`) e tinha erro de locale na coluna por 100. Os logs estão em `evidencias/rodada1-janela-curta/`, com uma nota explicativa. A tabela acima é da rodada 2, corrigida.

## Critérios de aceite

- [x] A versão quebrada apresenta falhas mensuráveis: 333 em 11.232 (2,96 por 100)
- [x] A versão final apresenta zero falhas em ≥500 requisições consecutivas durante um rollout completo: 23.658
- [x] A explicação identifica a corrida entre a atualização dos Endpoints/iptables e o envio do SIGTERM
