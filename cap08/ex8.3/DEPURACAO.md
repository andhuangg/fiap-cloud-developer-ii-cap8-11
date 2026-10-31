# Exercício 8.3: Depuração (Job estourado, Secret inválido e Service sem endpoints)

Ambiente: minikube (perfil `cp-bara`), Kubernetes v1.33.1, namespace `store-dev`.
Saídas completas, com o comando e o horário de cada execução, em `evidencias/`.
Manifestos quebrados e corrigidos em `manifestos/`.

---

## Cenário A: Job `relatorio-quebrado` (backoffLimit: 2, restartPolicy: Never)

**(i) Estado observado.** O Job terminou `Failed 0/1`, com **3 Pods em `Error`** (1 tentativa + 2 retentativas). Como `restartPolicy: Never`, cada retentativa cria um Pod novo em vez de reiniciar o container. Os intervalos entre as criações (0s, 11s, 31s) mostram o backoff exponencial do job-controller.

```
NAME                       READY   STATUS   RESTARTS   AGE
relatorio-quebrado-2knf6   0/1     Error    0          50s
relatorio-quebrado-2swmj   0/1     Error    0          19s
relatorio-quebrado-qg5t8   0/1     Error    0          39s
```

**(ii) Comando que revelou a causa e mensagem exata.**

- `kubectl describe job relatorio-quebrado -n store-dev` mostra `Pods Statuses: 0 Active / 0 Succeeded / 3 Failed` e o evento:
  `Warning  BackoffLimitExceeded  job-controller  Job has reached the specified backoff limit`
- Condição do Job: `Failed=True reason=BackoffLimitExceeded`.
- `kubectl logs` de um dos Pods mostra a causa raiz:
  `cat: can't open '/dados/vendas.csv': No such file or directory` (exitCode=1 nos 3 Pods).

**(iii) Correção.** O template de um Job é imutável, então o Job foi deletado e recriado (`manifestos/A-job-corrigido.yaml`) com o arquivo de entrada existindo antes da leitura.

**(iv) Evidência da correção.** `relatorio-quebrado   Complete   1/1`, com log `gerando relatorio` / `produto,qtd`.

---

## Cenário B: Secret com base64 inválido e base64 com quebra de linha

### B1: valor que não é base64 válido no campo `data:`

**(i) Estado observado.** O Secret nem é criado. O API server rejeita o objeto na desserialização.

**(ii) Comando e mensagem exata.** `kubectl apply -f manifestos/B1-secret-base64-invalido.yaml`:

```
Error from server (BadRequest): error when creating "manifestos/B1-secret-base64-invalido.yaml": Secret in version "v1" cannot be handled as a Secret: illegal base64 data at input byte 5
```

O byte 5 é o `@` de `senha@123!`, fora do alfabeto base64.

> Observação de laboratório: a primeira tentativa usou `senha123` e **foi aceita**, porque `senha123` tem 8 caracteres do alfabeto base64 e por acaso é base64 válido (decodifica para lixo binário). Ou seja, o API server não protege contra quem esquece de codificar: ele só rejeita quando a string é sintaticamente inválida.

**(iii) Correção.** Usar `stringData:` (o API server codifica sozinho) ou codificar corretamente com `echo -n`. Ver `manifestos/B-secrets-corrigidos.yaml`.

**(iv) Evidência.** `secret/db-secret-invalido created`; decodificado: `senha@123!`.

### B2: base64 válido porém gerado com `echo 'senha' | base64` (sem `-n`)

**(i) Estado observado.** O Secret é aceito e o Pod sobe normalmente. A falha é silenciosa: a aplicação recebe a senha com um `\n` no final e a autenticação no banco falharia.

**(ii) Comando e evidência numérica.**

```
$ echo 'senha' | base64        -> c2VuaGEK   (com \n)
$ echo -n 'senha' | base64     -> c2VuaGE=   (correto)

$ kubectl logs teste-senha -n store-dev
tamanho esperado de 'senha': 5
tamanho de $DB_PASSWORD: 6
0000000   s   e   n   h   a  \n

$ kubectl exec teste-senha -- sh -c 'printf "%s" "$DB_PASSWORD" | wc -c'
6
```

**(iii) Correção.** Regerar com `echo -n 'senha' | base64` (`c2VuaGE=`) e recriar o Pod. A variável de ambiente só é lida na criação do container.

**(iv) Evidência.** `tamanho de $DB_PASSWORD: 5` e `od -c` sem o `\n`.

---

## Cenário C: Service sem endpoints

### C1: selector `app: storeapi` (sem hífen) contra a label `app: store-api`

**(i) Estado observado.** Pods `1/1 Running`, mas o Service não tem backends.

```
$ kubectl get endpointslices -l kubernetes.io/service-name=store-api -o wide
NAME              ADDRESSTYPE   PORTS     ENDPOINTS   AGE
store-api-t4vz8   IPv4          <unset>   <unset>     5s
$ kubectl get endpoints store-api
store-api   <none>
```

**(ii) Comando que revelou a causa.** `kubectl describe svc store-api` mostra `Selector: app=storeapi`, enquanto `kubectl get pods --show-labels` mostra `app=store-api`. `kubectl get pods -l app=storeapi` retorna `No resources found`. Teste de conexão a partir do Pod `cliente`:

```
curl: (7) Failed to connect to store-api port 80 after 9 ms: Could not connect to server
```

**(iii) Correção.** `selector: app: store-api` (`manifestos/C-service-corrigido.yaml`).

**(iv) Evidência.** EndpointSlice com `10.244.0.24,10.244.0.25` na porta 8000 e `curl` retornando `{"status":"ok","host":"store-api-5f986f48b9-4b8bp"}`.

### C2: selector correto, readinessProbe apontando para `/pronto` (não existe)

**(i) Estado observado.** Pods em `Running` mas `0/1` READY. O Service fica sem backend utilizável, mesmo com o selector correto.

```
NAME                         READY   STATUS    RESTARTS   AGE
store-api-6b6458f88b-4r74d   0/1     Running   0          35s
store-api-6b6458f88b-dl9gt   0/1     Running   0          35s

$ kubectl get endpoints store-api        -> ENDPOINTS vazio
$ endpointslice: 10.244.0.30 ready=false / 10.244.0.29 ready=false
```

Diferença importante: o EndpointSlice **lista os IPs**, mas com `conditions.ready=false`, e o kube-proxy só programa os endpoints `ready`. O `Endpoints` legado mostra a coluna vazia. Por isso a conexão falha igual à causa C1.

**(ii) Comando que revelou a causa.** `kubectl describe pod` mostra `Ready False` e `ContainersReady False` nas Conditions, mais o evento:

```
Warning  Unhealthy  2s (x9 over 34s)  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 404
```

A chamada direta ao Pod confirma: `curl http://10.244.0.30:8000/pronto` retorna `404`. Via Service: `curl: (7) Failed to connect to store-api port 80`.

Durante a reprodução apareceu um detalhe a mais: ao aplicar a probe quebrada **por cima** de um Deployment saudável, o rolling update trava (`1 out of 2 new replicas have been updated`) e os Pods antigos (Ready) continuam no Service. O endpoint não esvazia, e o sintoma vira um rollout preso. Para isolar a causa, o Deployment foi recriado do zero com a probe quebrada (registrado em `evidencias/C-service.txt`).

**(iii) Correção.** readinessProbe de volta para `/ready` (`manifestos/C-deployment.yaml`).

**(iv) Evidência.** `deployment "store-api" successfully rolled out`, Pods `1/1`, EndpointSlice com `10.244.0.31,10.244.0.32` e `curl` retornando `{"status":"ok",...}`.
