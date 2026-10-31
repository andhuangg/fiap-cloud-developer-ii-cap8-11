# Exercício 9.2: Usuário por certificado com kubeconfig funcional

Usuário `joao.qa`, grupo `fiap:qa`, minikube (perfil `cp-bara`), Kubernetes v1.33.1.
Saída bruta de cada comando, com horário: `saidas.txt`.

Arquivos: `joao-qa.key`, `joao-qa.csr`, `joao-qa.crt`, `csr-joao.yaml`, `kubeconfig-joao.yaml`, `rbac-qa.yaml` (junção de `binding-view.yaml` e `role-exec.yaml`, que foram aplicados separadamente).

## Fluxo de emissão

1. `openssl genrsa -out joao-qa.key 2048`
2. `openssl req -new -key joao-qa.key -out joao-qa.csr -subj "/CN=joao.qa/O=fiap:qa"`. O `CN` vira o **usuário** e o `O` vira o **grupo**.
3. `CertificateSigningRequest` (`csr-joao.yaml`) com `signerName: kubernetes.io/kube-apiserver-client` e `expirationSeconds: 604800` (7 dias). O CSR entra `Pending`, é aprovado com `kubectl certificate approve joao.qa` e passa a `Approved,Issued`.
4. Certificado extraído de `.status.certificate`. Saída pedida:

```
$ openssl x509 -in joao-qa.crt -noout -subject -dates
subject=O=fiap:qa, CN=joao.qa
notBefore=Oct 31 20:16:21 2026 GMT
notAfter=Nov  7 20:16:21 2026 GMT
```

O subject é `CN = joao.qa, O = fiap:qa` e a validade é de exatamente 7 dias. A ordem `O=` e `CN=` impressa pelo openssl é só de apresentação.

5. `kubeconfig-joao.yaml` montado com `--embed-certs=true`. Contém `certificate-authority-data`, `client-certificate-data` e `client-key-data`, sem nenhuma referência a arquivo. **Teste de isolamento:** copiado sozinho para um diretório vazio, `KUBECONFIG=./kubeconfig-joao.yaml kubectl get pods -n store-dev` funcionou (ver `saidas.txt`, depois do binding).

## (a) Antes de qualquer binding: 403, e não 401

```
$ kubectl --kubeconfig=kubeconfig-joao.yaml auth whoami
Username  joao.qa
Groups    [fiap:qa system:authenticated]

$ kubectl --kubeconfig=kubeconfig-joao.yaml get pods -n store-dev
Error from server (Forbidden): pods is forbidden: User "joao.qa" cannot list resource "pods" in API group "" in the namespace "store-dev"
(HTTP: status="403 Forbidden")
```

Para contrastar, um certificado **não assinado pela CA do cluster** (autoassinado, mesmo CN e O):

```
error: You must be logged in to the server (Unauthorized)      # HTTP 401
```

**Diferença.**
- **401 Unauthorized = falha de autenticação**: o API server não sabe quem é o cliente (certificado não confiável, token inválido ou expirado). Nenhuma regra de RBAC chega a ser avaliada.
- **403 Forbidden = falha de autorização**: o API server sabe exatamente quem é (o `whoami` mostra `joao.qa` e o grupo `fiap:qa`), mas nenhuma regra RBAC permite a ação. RBAC é *deny by default*, então identidade válida sem binding recebe 403.

## (b) Permissão vinda do grupo (RoleBinding com `kind: Group`)

`binding-view.yaml` associa o **grupo** `fiap:qa` (e não o usuário) ao ClusterRole `view` no namespace `store-dev`.

```
$ kubectl --kubeconfig=kubeconfig-joao.yaml get pods -n store-dev
NAME                         READY   STATUS      ...
cliente                      1/1     Running
store-api-5f986f48b9-n7vsr   1/1     Running
...
$ kubectl --kubeconfig=kubeconfig-joao.yaml get pods -n store-prod
Error from server (Forbidden): ... in the namespace "store-prod"
```

**Prova de que veio do `O=` do certificado:** o binding só cita `fiap:qa`, e o nome `joao.qa` não aparece em nenhum binding. Em `can-i` com impersonation:

```
kubectl auth can-i list pods -n store-dev --as=joao.qa                      -> no
kubectl auth can-i list pods -n store-dev --as=joao.qa --as-group=fiap:qa   -> yes
```

Só o usuário, sem o grupo, não tem acesso. Com o grupo (que o certificado declara em `O=`), tem. O `view` vale só em `store-dev`: em `store-prod` o João segue em 403.

## (c) `pods/exec` apenas em `store-dev`

`role-exec.yaml`: Role `qa-exec` com `pods/exec` + `create`, e RoleBinding para o grupo, ambos em `store-dev`.

```
# antes da Role
Error from server (Forbidden): pods "store-api-..." is forbidden: User "joao.qa" cannot create resource "pods/exec" in API group "" in the namespace "store-dev"

# depois
$ kubectl --kubeconfig=kubeconfig-joao.yaml exec -n store-dev store-api-5f986f48b9-n7vsr -- id
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)

$ kubectl --kubeconfig=kubeconfig-joao.yaml exec -n store-prod alvo -- id
Error from server (Forbidden): pods "alvo" is forbidden: User "joao.qa" cannot get resource "pods" in API group "" in the namespace "store-prod"
```

```
can-i create pods --subresource=exec -n store-dev   -> yes
can-i create pods --subresource=exec -n store-prod  -> no
can-i delete pods -n store-dev                      -> no   (exec não dá outras permissões)
```

Dois pontos de honestidade sobre este item:

1. Em `store-prod` o erro é `cannot get pods` e não `cannot create pods/exec`, porque o `kubectl exec` faz primeiro um GET no Pod, e o João não tem nenhuma permissão lá. Para isolar a regra do `pods/exec`, o `can-i --subresource=exec` mostra `no` em prod.
2. Ao testar, `kubectl auth can-i create pods/exec` (forma abreviada) devolveu `no` mesmo com o `exec` real funcionando. Com `--subresource=exec` a resposta passa a ser a correta. Não investiguei a causa, e por isso usei `--subresource` nas provas. Os resultados da forma abreviada ficaram registrados em `saidas.txt`, com uma nota.

## (d) Revogação: o certificado continua autenticando

Removidos `qa-view`, `qa-exec` (RoleBinding) e a Role `qa-exec`:

```
$ kubectl --kubeconfig=kubeconfig-joao.yaml auth whoami
Username  joao.qa    Groups  [fiap:qa system:authenticated]

$ kubectl --kubeconfig=kubeconfig-joao.yaml get pods -n store-dev
Error from server (Forbidden): pods is forbidden: User "joao.qa" cannot list resource "pods" ...
```

O erro volta a ser **403 Forbidden**, nunca 401: o certificado continua válido (até 07/11/2026) e a identidade continua sendo reconhecida. O Kubernetes **não tem revogação de certificado** (não há CRL nem OCSP). Remover as permissões do RBAC nega o acesso, mas a identidade continua existindo. Para invalidar de fato, só trocando a CA do cluster. Por isso se usa `expirationSeconds` curto e se prefere OIDC para humanos.

## Critérios de aceite

- [x] `kubeconfig-joao.yaml`, copiado para um diretório vazio, executa `kubectl get pods -n store-dev` com sucesso
- [x] Subject do certificado: `CN = joao.qa, O = fiap:qa`
- [x] `exec` funciona em `store-dev` e retorna `Forbidden` em `store-prod`
- [x] Após a revogação o erro é `Forbidden` (403), não `Unauthorized` (401)
