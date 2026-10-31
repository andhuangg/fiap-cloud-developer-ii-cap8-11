# Exercício 10.4: Componente serverless

## Item que deixa de fazer sentido no AWS Lambda

**Item do checklist:** *"Imagem base mínima (distroless/alpine/chainguard), multi-stage build"*, junto com *"`USER` numérico não-root"*.

No EKS, a FIAP Store escolhe, constrói e corrige o sistema operacional dentro da imagem. No ex. 10.2, foram os 469 CVEs do Debian da `python:3.12` contra os 62 do distroless.

No Lambda com runtime gerenciado (`python3.12` em pacote zip), quem fornece o sistema operacional, o interpretador e o usuário de execução é a AWS. Ela aplica os patches de SO e de runtime sem deploy nosso, e a função já roda sem privilégio, num micro-VM Firecracker isolado. Não existe imagem base para escolher nem `USER` para declarar.

A linha da responsabilidade compartilhada **sobe**: o SO e o runtime passam para o lado da AWS. Do nosso lado sobram o código e as dependências.

Ressalva: se a função for empacotada como imagem de container, a escolha da base volta a ser nossa.

## Item que continua exatamente igual

**Item do checklist:** *"Scan sem CVE CRITICAL corrigível (Trivy no CI com `--exit-code 1`)"*, aplicado às **dependências da aplicação**.

O `starlette 0.41.3` com CVE-2025-62727, encontrado no ex. 10.2, seria tão vulnerável dentro de um Lambda quanto dentro de um Pod. A AWS corrige o runtime Python, mas **nunca** mexe no `requirements.txt` de ninguém: o pacote que você sobe é seu. O mesmo `trivy fs --scanners vuln --exit-code 1 --ignore-unfixed .` precisa barrar o pipeline nos dois mundos.

Aqui a linha **não se move**: tudo acima do runtime (código, bibliotecas, configuração e permissões, que no Lambda viram a IAM execution role em vez do RBAC) continua sendo responsabilidade do cliente em qualquer modelo de nuvem.

## Extra opcional: Knative Service (`extra-knative/store-api-knative.yaml`)

O manifesto Knative equivalente à `store-api` de prod (`min-scale: 0`, `max-scale: 20`) elimina ou absorve estes itens do checklist:

| Item do checklist | Com Knative |
|---|---|
| HPA configurado com métrica real | **eliminado**: o KPA escala por concorrência de requisições (`target: 50`), que representa a carga real melhor que CPU |
| `strategy.rollingUpdate` com `maxUnavailable: 0` | **eliminado**: cada mudança gera uma Revision imutável, e a troca de tráfego é feita pela Route, que só aponta para a nova quando ela está pronta |
| `preStop` + `terminationGracePeriodSeconds` | **absorvido**: o `queue-proxy` (sidecar do Knative) drena as requisições em voo antes de liberar o encerramento |
| `replicas >= 2` fixas | **substituído** por escala dinâmica de 0 a 20 (com o custo do cold start; para manter disponibilidade usa-se `min-scale: 1`) |

**4 itens** a menos para manter à mão. Todos os itens de **segurança** continuam iguais: securityContext, PSA, NetworkPolicy, scan e Secrets fora do Git. O Knative, assim como o Lambda, tira de você a mecânica de escalar e de trocar versão, mas não tira a responsabilidade pelo que roda dentro do container.

Observação: o manifesto foi validado apenas como YAML. O Knative Serving não foi instalado no laboratório do capítulo 10 (no capítulo 11, exercício 11.4, um Knative Service é efetivamente gerenciado pelo Argo CD).
