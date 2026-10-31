# Exercício 8.2: CronJob com concorrência controlada e Secret de duas formas

minikube (perfil `cp-bara`), Kubernetes v1.33.1, namespace `store-dev`.

| Arquivo | Conteúdo |
|---|---|
| `sincroniza-cronjob-allow.yaml` | versão 1 (`concurrencyPolicy: Allow`) |
| `sincroniza-cronjob-forbid.yaml` | versão 2 (`concurrencyPolicy: Forbid`) |
| `catalogo-secret.yaml` | Secret `catalogo-secret` com a chave `API_TOKEN` |
| `evidencias/01-allow.txt` | amostras a cada 30 s da fase Allow (12 min) |
| `evidencias/02-forbid.txt` | amostras da fase Forbid (12 min), `describe` e eventos |
| `evidencias/03-secret-env-x-volume.txt` | `printenv` x `cat` antes e depois do patch |

A execução foi automatizada pelo script `run-8.2.sh` que aplicava os manifestos, tirava uma foto de `kubectl get cronjob,jobs,pods` + `.status.active` a cada 30 s e trocava a política após 12 minutos.

Configuração comum às duas versões: `schedule: "*/5 * * * *"`, `timeZone: "America/Sao_Paulo"`, `startingDeadlineSeconds: 120`, `successfulJobsHistoryLimit: 2`, `failedJobsHistoryLimit: 1`, e um container que dura **6 minutos** (`sleep 360`). Ou seja, cada execução ainda está rodando quando chega a seguinte.

> O nome de cada Job é `sincroniza-catalogo-<minutos desde a época Unix>` do horário agendado. `29891295` é 17:15, `29891300` é 17:20, e assim por diante. Isso permite saber a qual horário cada Job pertence.

## Fase 1: `concurrencyPolicy: Allow` (17:12 a 17:24)

Linha do tempo extraída de `.status.active`:

| Horário | Jobs ativos | Quais |
|---|---|---|
| 17:12:05 | 0 | (CronJob criado) |
| 17:15:06 | 1 | `...295` (17:15) |
| **17:20:10** | **2** | `...295` (17:15) **e** `...300` (17:20) |
| 17:21:11 | 1 | `...300` (o de 17:15 terminou após 6 min) |

Foto das 17:20:10 (`evidencias/01-allow.txt`):

```
NAME                                SCHEDULE      TIMEZONE            SUSPEND   ACTIVE   LAST SCHEDULE
cronjob.batch/sincroniza-catalogo   */5 * * * *   America/Sao_Paulo   False     2        11s
job.batch/sincroniza-catalogo-29891295   Running    0/1   5m11s
job.batch/sincroniza-catalogo-29891300   Running    0/1   11s
pod/sincroniza-catalogo-29891295-bxdv9   1/1   Running   5m11s
pod/sincroniza-catalogo-29891300-6v7fm   1/1   Running   11s
jobs ativos (.status.active): sincroniza-catalogo-29891295 sincroniza-catalogo-29891300
```

Com `Allow` o controller cria o Job novo sem olhar o anterior: **2 Jobs simultâneos**, e os dois sincronizariam o mesmo catálogo ao mesmo tempo (risco de escrita concorrente).

## Fase 2: `concurrencyPolicy: Forbid` (17:24 a 17:36)

| Horário | Jobs ativos | O que aconteceu |
|---|---|---|
| 17:24:13 | 1 | `...300` (17:20) ainda rodando; a política foi trocada aqui |
| 17:25 | 1 | horário das 17:25 chega com `...300` ativo, então o controller **não cria** e registra `JobAlreadyActive` |
| 17:26:16 | 1 | `...300` termina, e o `...305` (o **das 17:25**) é criado com 1 min de atraso |
| 17:30 | 1 | `...305` ainda ativo, então `JobAlreadyActive` de novo |
| 17:32:30 | 0 | `...305` termina, mas o horário das 17:30 já passou dos 120 s do `startingDeadlineSeconds`, e **não existe Job `...310`** |
| 17:35:02 | 1 | `...315` (17:35) criado normalmente |

Nunca houve mais de 1 Job ativo. Evento do `kubectl describe cronjob sincroniza-catalogo` (`evidencias/02-forbid.txt`):

```
Concurrency Policy:            Forbid
Events:
  Normal  JobAlreadyActive  6m33s (x4 over 11m)  cronjob-controller  Not starting job because prior execution is running and concurrency policy is Forbid
```

**Achado da medição:** com `Forbid`, "pular" depende do `startingDeadlineSeconds`. O controller tenta de novo a cada ciclo de sincronização (por isso o `x4`), enquanto estiver dentro do prazo de 120 s:

- **17:25:** o anterior terminou às ~17:26, ainda dentro do prazo, então a execução foi **atrasada**, e não perdida.
- **17:30:** o anterior só terminou às ~17:32, fora do prazo, então a execução foi **perdida** de vez.

Sem `startingDeadlineSeconds`, a execução perdida seria simplesmente descartada (e o controller ainda contaria horários perdidos, podendo recusar agendar após 100 perdas).

## Histórico de Jobs (`successfulJobsHistoryLimit: 2`)

O maior número de Jobs `Complete` listados ao mesmo tempo nas amostras foi **2**. Quando o terceiro concluiu, o controller apagou o mais antigo:

```
Normal  SawCompletedJob   cronjob-controller  Saw completed job: sincroniza-catalogo-29891305, condition: Complete
Normal  SuccessfulDelete  cronjob-controller  Deleted job sincroniza-catalogo-29891295
```

## Secret consumido como env e como arquivo, no MESMO Pod

O mesmo Secret `catalogo-secret` é consumido duas vezes pelo container:

- como **variável de ambiente** `API_TOKEN` (`secretKeyRef`);
- como **arquivo** `/etc/catalogo/token` (volume `secret` com `items` e `defaultMode: 0400`).

Durante a execução ativa do Pod `sincroniza-catalogo-29891295-bxdv9` (`evidencias/03-secret-env-x-volume.txt`):

```
# 17:16:08 ANTES do patch
printenv API_TOKEN          -> token-v1-original
cat /etc/catalogo/token     -> token-v1-original
ls -lL /etc/catalogo/token  -> -r--------  1 root root 17 ... /etc/catalogo/token     (0400)

kubectl patch secret catalogo-secret -p '{"stringData":{"API_TOKEN":"token-v2-rotacionado"}}'
secret/catalogo-secret patched

# 17:17:38 DEPOIS do patch, 90 s, MESMO Pod
printenv API_TOKEN          -> token-v1-original       <- variável NÃO mudou
cat /etc/catalogo/token     -> token-v2-rotacionado    <- arquivo MUDOU
```

**Por quê.**
- **Variável de ambiente:** é resolvida **uma única vez**, quando o container é criado. Ela vira parte do ambiente do processo, e o kubelet não tem como alterá-la depois. Só um Pod novo enxerga o valor novo.
- **Volume `secret`:** é sincronizado periodicamente pelo kubelet. Ele grava a nova versão num diretório com timestamp e troca o symlink `..data` de forma atômica. Por isso o `ls -lL` (seguindo o link) mostra o arquivo, e a troca chega em até ~1 min (período de sync do kubelet + cache).
- **Exceção:** se o volume fosse montado com `subPath`, o arquivo também **não** seria atualizado.

**Consequência prática para a FIAP Store:** para rotacionar o token da API do catálogo sem reiniciar Pods, a aplicação precisa **ler o arquivo** a cada uso (ou observar mudanças nele). Se ela usar variável de ambiente, a rotação exige um `kubectl rollout restart`.

## Critérios de aceite

- [x] Com `Allow` existiram 2 Jobs simultaneamente ativos (17:20:10)
- [x] Com `Forbid` no máximo 1 ativo, e o `describe` mostra `JobAlreadyActive`: "Not starting job because prior execution is running and concurrency policy is Forbid"
- [x] O histórico nunca passou de 2 Jobs concluídos (o 3º disparou `SuccessfulDelete` do mais antigo)
- [x] No mesmo Pod, o arquivo foi atualizado e a variável de ambiente continuou com o valor antigo
