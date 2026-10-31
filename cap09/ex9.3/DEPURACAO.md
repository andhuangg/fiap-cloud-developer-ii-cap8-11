# Exercício 9.3: Depuração, quatro erros "Forbidden" reais

minikube (perfil `cp-bara`), Kubernetes v1.33.1. Os usuários foram simulados com `--as=user.x`, então todas as mensagens abaixo são **respostas reais do API server** do cluster, copiadas de `evidencias/` (com comando e horário).
YAMLs: `antes/` (quebrado) e `depois/` (corrigido). Diff de cada Role dentro de cada seção.

**Como ler a mensagem.** Todo erro do RBAC segue o molde:
`<recurso> is forbidden: User "<sujeito>" cannot <verbo> resource "<recurso>" in API group "<apiGroup>" in the namespace "<namespace>"`

---

## Cenário A: Role com `pods`, mas o usuário roda `kubectl logs`

**Mensagem exata**

```
Error from server (Forbidden): pods "store-api-5f986f48b9-n7vsr" is forbidden: User "user.a" cannot get resource "pods/log" in API group "" in the namespace "store-dev"
```

| Elemento | Valor |
|---|---|
| Sujeito | `user.a` |
| Verbo | `get` |
| Recurso | `pods/log` (subresource) |
| apiGroup | `""` (core) |
| Namespace | `store-dev` |

**Por que falha.** `pods/log` é um *subresource*, com regra RBAC própria. Conceder `pods` não concede `pods/log`, nem `pods/exec`. O `kubectl logs` faz `GET /api/v1/namespaces/store-dev/pods/<pod>/log`.

**Correção mínima** (adiciona só `pods/log`, mantendo os mesmos verbos):

```diff
-    resources: ["pods"]
+    resources: ["pods", "pods/log"]
```

**Prova da correção:** `kubectl logs ... --as=user.a` passa a retornar `INFO: Started server process [1]...`; `can-i get pods --subresource=log` retorna `yes`.

**Prova de que continua mínima (adjacente negado):**

```
kubectl auth can-i create pods --subresource=exec -n store-dev --as=user.a   -> no
kubectl exec ... --as=user.a -- id
Error from server (Forbidden): ... User "user.a" cannot create resource "pods/exec" ...
kubectl auth can-i delete pods -n store-dev --as=user.a                      -> no
```

> **Armadilha de diagnóstico encontrada.** Antes da correção, `kubectl auth can-i get pods/log` (forma abreviada) respondeu **`yes`**, enquanto o `kubectl logs` real dava Forbidden. Com `--subresource=log` a resposta foi `no`, a correta. Ou seja, o atalho `recurso/subrecurso` do `can-i` neste kubectl (v1.33.1) enganou nos dois sentidos (no 9.2 negou um `exec` que funcionava). Não confirmei a causa. Usei `--subresource` nas provas e recomendo confirmar com o comando real.

---

## Cenário B: Role com `deployments` no `apiGroups: [""]`

**Mensagem exata**

```
Error from server (Forbidden): deployments.apps is forbidden: User "user.b" cannot list resource "deployments" in API group "apps" in the namespace "store-dev"
```

| Elemento | Valor |
|---|---|
| Sujeito | `user.b` |
| Verbo | `list` |
| Recurso | `deployments` |
| apiGroup | **`apps`** |
| Namespace | `store-dev` |

**Identificação do erro.** A mensagem diz que o API server precisa de `deployments` no grupo `apps`, mas a Role (`kubectl get role cenario-b -o jsonpath='{.rules}'`) tem `"apiGroups":[""]`. O grupo `""` é o core (Pods, Services, ConfigMaps...). `Deployment` mora em `apps/v1`.

**Correção mínima** (só o apiGroup, nenhum verbo ou recurso a mais):

```diff
-  - apiGroups: [""]
+  - apiGroups: ["apps"]
     resources: ["deployments"]
```

**Prova da correção:** `kubectl get deployments --as=user.b` lista `app-teste`, `redis` e `store-api`; `can-i list deployments.apps` retorna `yes`.

**Adjacente continua negado:**

```
can-i delete deployments.apps  -> no
can-i list statefulsets.apps   -> no   (mesmo apiGroup, outro recurso)
kubectl get statefulsets --as=user.b
Error from server (Forbidden): statefulsets.apps is forbidden: User "user.b" cannot list resource "statefulsets" in API group "apps" ...
can-i list pods                -> no   (outro apiGroup)
```

---

## Cenário C: `create` e `update` em `deployments` (apps), mas o `kubectl apply` falha

**Mensagem exata**

```
Error from server (Forbidden): error when retrieving current configuration of:
Resource: "apps/v1, Resource=deployments", GroupVersionKind: "apps/v1, Kind=Deployment"
Name: "app-teste", Namespace: "store-dev"
from server for: "deploy-v2.yaml": deployments.apps "app-teste" is forbidden: User "user.c" cannot get resource "deployments" in API group "apps" in the namespace "store-dev"
```

| Elemento | Valor |
|---|---|
| Sujeito | `user.c` |
| Verbo | `get` |
| Recurso | `deployments` |
| apiGroup | `apps` |
| Namespace | `store-dev` |

Curiosidade do diagnóstico: `can-i create` e `can-i update` retornam `yes`, e mesmo assim o `apply` falha. O `can-i` confirma o que a Role *tem*, não o que o comando *precisa*.

**Quais verbos o `apply` realmente exige.** Requisições HTTP reais (`kubectl apply -v=8`):

```
"Request" verb="GET"   url=".../apis/apps/v1/namespaces/store-dev/deployments/app-teste"
"Request" verb="PATCH" url=".../apis/apps/v1/namespaces/store-dev/deployments/app-teste?fieldManager=kubectl-client-side-apply..."
```

O `apply` (client-side) primeiro lê o objeto atual (**`get`**, para calcular o diff com a anotação `last-applied`) e depois envia um **`patch`**. Para um objeto novo faz `get` (404) + `create`. Ele **não usa `update` (PUT)**. Nota: mantive `update` na Role porque o enunciado pede só *adicionar*, mas ele é desnecessário para o `apply`.

**Correção mínima** (adiciona só `get` e `patch`):

```diff
-    verbs: ["create","update"]
+    verbs: ["create","update","get","patch"]
```

**Prova da correção:** `kubectl apply -f deploy-v2.yaml --as=user.c` retorna `deployment.apps/app-teste configured` e `replicas` passa de 1 para 2.

**Adjacente continua negado:**

```
can-i delete deployments.apps -n store-dev --as=user.c   -> no
can-i list deployments.apps   -n store-dev --as=user.c   -> no
kubectl delete deploy app-teste --as=user.c
Error from server (Forbidden): ... User "user.c" cannot delete resource "deployments" in API group "apps" ...
```

---

## Cenário D: RoleBinding em `store-dev` para ClusterRole `edit`, usuário opera em `store-prod`

**Mensagem exata**

```
Error from server (Forbidden): pods is forbidden: User "user.d" cannot list resource "pods" in API group "" in the namespace "store-prod"
```

| Elemento | Valor |
|---|---|
| Sujeito | `user.d` |
| Verbo | `list` |
| Recurso | `pods` |
| apiGroup | `""` (core) |
| Namespace | **`store-prod`** |

**Causa.** Um RoleBinding só vale **no namespace em que foi criado**, mesmo apontando para um ClusterRole. `kubectl get rolebinding -A | grep user-d` mostrava apenas `store-dev   user-d-edit`. Em `store-dev` o usuário lista Pods normalmente, e em `store-prod` não.

**Correção certa: um segundo RoleBinding em `store-prod`**, reaproveitando o mesmo ClusterRole `edit` (`depois/D.yaml`).

**Prova:** `kubectl get pods -n store-prod --as=user.d` passa a funcionar (`No resources found`, sem erro), `can-i create deployments.apps -n store-prod` retorna `yes`, e há agora um `user-d-edit` em cada namespace.

**Adjacente continua negado:** `can-i list pods -n kube-system --as=user.d` retorna `no`.

**Por que `ClusterRoleBinding` seria a solução errada.** Foi testado de verdade, com um binding temporário (já removido):

```
kubectl create clusterrolebinding user-d-crb-temp --clusterrole=edit --user=user.d
can-i list pods               -n kube-system --as=user.d  -> yes
can-i create deployments.apps -n kube-system --as=user.d  -> yes
can-i delete secrets          -n kube-system --as=user.d  -> yes
can-i get secrets             -n kube-system --as=user.d  -> yes
kubectl delete clusterrolebinding user-d-crb-temp
can-i list pods               -n kube-system --as=user.d  -> no
```

O ClusterRoleBinding concede o papel em **todos os namespaces**, incluindo `kube-system`, onde o `edit` permite ler e apagar Secrets (tokens de ServiceAccount do control plane) e criar Deployments. Isso viola o menor privilégio: o pedido era "também em `store-prod`", e não "em todo o cluster, para sempre, inclusive em namespaces futuros". A forma correta é um RoleBinding por namespace, reaproveitando o ClusterRole (que, usado via RoleBinding, serve só como *molde de regras*).

---

## Critérios de aceite

- [x] Quatro mensagens reais capturadas do cluster, e não inventadas
- [x] Cenário A adiciona **apenas** `pods/log` (e `pods/exec` segue negado)
- [x] Cenário C adiciona **apenas** `get` e `patch`
- [x] Cenário D resolvido com um segundo RoleBinding em `store-prod`, com justificativa escrita contra o ClusterRoleBinding
