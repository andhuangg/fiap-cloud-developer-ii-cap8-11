# Exercício 8.4: Comparação de arquiteturas para a fila de pedidos da FIAP Store

Trilha escolhida: **A (KEDA)**, executada de verdade no minikube (`keda-scaledjob.yaml`, evidências em `evidencias/`).

Arquiteturas comparadas para o mesmo problema (consumir a fila de pedidos):

1. **Job com `parallelism` fixo**: um Job com N Pods consumindo a fila até esvaziar.
2. **KEDA ScaledJob**: o KEDA consulta a fila e cria de 0 a `maxReplicaCount` Jobs conforme o tamanho dela.
3. **SQS + Lambda com event source mapping (ESM)**: a AWS faz o polling da fila e invoca a função em lotes.

Premissas usadas nos números: cada pedido leva 3 s de processamento (igual ao laboratório), região us-east-1, preços on-demand de referência: `t3.medium` US$ 0,0416/h, control plane EKS US$ 0,10/h, Lambda US$ 0,20 por 1 milhão de requisições e US$ 0,0000166667 por GB-segundo (x86), SQS Standard US$ 0,40 por milhão de requisições.

## 1. Comportamento sob pico de 10.000 mensagens

- **Job fixo (parallelism 10):** 10.000 × 3 s / 10 = 3.000 s, ou seja, **50 min** para drenar. O Job não reage ao tamanho da fila: alguém (ou um CronJob) precisa criá-lo, e o paralelismo é o mesmo com 10 ou com 10.000 mensagens.
- **KEDA ScaledJob:** com `listLength: 5`, o alvo seria 2.000 Jobs, mas o `maxReplicaCount` corta em 10. Com max 10 o tempo é igual ao do Job fixo (50 min). A diferença é que a escala acontece sozinha, e com `maxReplicaCount: 100` cairia para cerca de **5 min**, desde que existam nodes. Nesse ponto quem limita é a capacidade do node group: um `t3.medium` (2 vCPU, 4 GiB) comporta da ordem de 15 a 20 workers de 100m CPU / 128 Mi, e o Cluster Autoscaler ou o Karpenter leva de 1 a 2 min para adicionar node.
- **SQS + Lambda:** com lote de 10, são 1.000 invocações de cerca de 30 s. O ESM sobe até 300 execuções concorrentes por minuto, chegando a até 1.250 (limitado pela cota da conta, 1.000 por padrão). O pico drena em **cerca de 2 a 3 min**, sem planejar capacidade.

## 2. Latência de cold start

- **Job fixo:** não há cold start por item, mas há o tempo de agendar o Pod e baixar a imagem na criação do Job (de 2 a 10 s com imagem em cache, até minutos sem cache).
- **KEDA:** medido no laboratório, os 50 itens entraram às 17:18:58, os Jobs foram criados em até 5 s (`pollingInterval: 5`) e os Pods estavam `Running` às 17:19:08. Ou seja, **cerca de 5 a 10 s** do primeiro item ao processamento, com a imagem em cache. Sem node disponível, soma-se o tempo de provisionar node (60 a 120 s).
- **Lambda:** cold start de Python fica tipicamente entre **200 ms e 1 s**. Mais o atraso do polling do ESM, que é próximo de zero com long polling.

## 3. Limite de tempo de execução por item

- **Job e KEDA:** **ilimitado** por padrão. Opcionalmente se coloca um teto com `activeDeadlineSeconds`. Serve para itens longos (relatório de fechamento, reprocessamento de catálogo).
- **Lambda:** **15 min** por invocação, no máximo. Com lote de 10 itens, cada item tem em média 90 s. Além disso, o visibility timeout da fila precisa ser de pelo menos 6× o timeout da função (recomendação da AWS), para a mensagem não reaparecer enquanto ainda está sendo processada.

## 4. Modelo de custo com números

Volume de referência: baixo no ano (10.000 pedidos por dia, 300 mil por mês) e Black Friday com 1 milhão de pedidos em um dia.

| Item | Job fixo / KEDA no EKS | SQS + Lambda (512 MB, lote 10) |
|---|---|---|
| Control plane | US$ 0,10/h × 730 h = **US$ 73,00/mês** | não existe |
| Compute ocioso | 2 × `t3.medium` × 730 h × 0,0416 = **US$ 60,74/mês**, mesmo com zero Pods | US$ 0 |
| Mês normal (300 mil pedidos) | já coberto pelos nodes | 30 mil invocações × 30 s × 0,5 GB = 450 mil GB-s. Descontando o free tier de 400 mil GB-s, sobram 50 mil × US$ 0,0000166667 = **US$ 0,83** + requisições (US$ 0,006) |
| Black Friday (1 milhão em 1 dia) | +5 `t3.medium` por 24 h = 5 × 24 × 0,0416 = **US$ 4,99** | 100 mil invocações × 15 GB-s = 1,5 milhão de GB-s = **US$ 25,00** |
| Fila | Redis no cluster (sem custo direto) ou SQS | SQS: cerca de 3 requisições por mensagem, 3 milhões × US$ 0,40/milhão = **US$ 1,20** no pico |

Observação: escala a zero de Pods com KEDA **não** é escala a zero de custo. Os nodes e o control plane continuam cobrando. O KEDA só zera o custo marginal se o node group também for a zero (Karpenter ou Cluster Autoscaler com `minSize: 0`). Mesmo assim, os US$ 73/mês do control plane ficam.

## 5. Tratamento de falhas

- **Job fixo:** `backoffLimit` define quantos Pods falhos o Job tolera, e passando disso ele vira `Failed` (`BackoffLimitExceeded`, como no ex. 8.3). O `podFailurePolicy` refina: `action: Ignore` para `DisruptionTarget` (node drenado não consome retentativa) e `action: FailJob` para códigos de saída que indicam bug (não adianta tentar de novo).
- **KEDA ScaledJob:** cada Job criado tem o próprio `backoffLimit`, e o `failedJobsHistoryLimit` guarda os falhos para inspeção. Achado importante do laboratório: o worker usa `LPOP`, que **remove o item antes de processar**. Se o Pod morrer no meio, o pedido se perde (at-most-once). O correto é o padrão de fila confiável: `LMOVE pedidos processando` + remoção só no sucesso, ou usar o próprio SQS como fila com o scaler `aws-sqs-queue` do KEDA.
- **SQS + Lambda:** at-least-once nativo. A mensagem só some quando a função retorna sucesso. Com `maxReceiveCount` (ex.: 3) na redrive policy, a mensagem que falha repetidamente vai para a **DLQ**, e com `ReportBatchItemFailures` só os itens que falharam no lote voltam para a fila. É o mecanismo mais completo dos três sem escrever código.

## Recomendação para a FIAP Store

Com o pico concentrado na Black Friday e volume baixo no resto do ano, a recomendação é **SQS + Lambda para o processamento de pedidos**:

- custa menos de US$ 1/mês no ano normal e cerca de US$ 26 no dia do pico, contra pelo menos US$ 134/mês fixos de EKS ocioso para o mesmo trabalho;
- drena 10.000 mensagens em minutos sem planejamento de capacidade;
- já entrega retentativa, DLQ e falha parcial de lote prontas.

O processamento de um pedido leva segundos, muito abaixo do limite de 15 min, então o limite do Lambda não pesa.

O **KEDA ScaledJob** continua sendo a escolha certa para o que não cabe no Lambda: tarefas longas (mais de 15 min), que precisam de acesso a recursos dentro do cluster, ou quando a empresa já paga o EKS pela `store-api` e quer portabilidade entre nuvens. Nesse caso, usar o scaler `aws-sqs-queue` (em vez de Redis com `LPOP`), Karpenter para os nodes acompanharem a escala e `podFailurePolicy` nos Jobs. O **Job com parallelism fixo** fica restrito a lotes previsíveis e agendados (via CronJob), onde não há variação de volume.
