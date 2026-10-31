# Exercício 9.4: Matriz de permissões do modelo RBAC da FIAP Store

Modelo: `rbac-modelo.yaml` (7 ClusterRoles molde + 10 RoleBindings + 1 ClusterRoleBinding).
Perfis representados por **grupos**: `fiap:dev`, `fiap:qa`, `fiap:sre`, `fiap:auditor`.

**Como a matriz foi gerada.** A tabela abaixo é a **saída literal** de `./testa-rbac.sh` (arquivo `MATRIZ-gerada.md`), não o que se esperava. Cada célula é o retorno de `kubectl auth can-i <verbo> <recurso> -n <ns> --as=teste.<perfil> --as-group=fiap:<perfil>`. Subresources usam `--subresource`, porque o atalho `pods/exec` do `can-i` se mostrou não confiável neste kubectl (ver 9.2 e 9.3).

**Evidência com identidades reais.** Além da matriz, foi emitido **um usuário por certificado para cada perfil** (`criar-usuario.sh`, pasta `usuarios/`): `ana.dev` (O=fiap:dev), `joao.qa2` (O=fiap:qa), `carla.sre` (O=fiap:sre) e `bruno.auditor` (O=fiap:auditor). Cada um executou comandos reais com o próprio kubeconfig (`evidencias-reais.txt`). Por exemplo: a `ana.dev` faz `exec` em store-dev e recebe Forbidden ao criar Deployment em store-prod; o `joao.qa2` cria e apaga Job em store-dev e recebe Forbidden em store-prod; a `carla.sre` lê `nodes` e `storageclasses` mas não consegue criar ClusterRoleBinding nem RoleBinding para si; o `bruno.auditor` lista RoleBindings mas recebe Forbidden em `secrets` e em `delete pod`.

Gerada em 2026-10-31 17:26:49 -03 a partir de `kubectl auth can-i --as=teste.<perfil> --as-group=fiap:<perfil>`
Contexto: cp-bara

### Recursos com namespace

| # | verbo recurso | dev @ dev | dev @ prod | qa @ dev | qa @ prod | sre @ dev | sre @ prod | auditor @ dev | auditor @ prod |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `get pods` | yes | yes | yes | yes | yes | yes | yes | yes |
| 2 | `get pods/log` | yes | yes | yes | yes | yes | yes | yes | yes |
| 3 | `create pods/exec` | yes | no | yes | no | yes | yes | no | no |
| 4 | `delete pods` | yes | no | no | no | yes | yes | no | no |
| 5 | `create deployments.apps` | yes | no | no | no | yes | yes | no | no |
| 6 | `delete deployments.apps` | yes | no | no | no | yes | yes | no | no |
| 7 | `patch horizontalpodautoscalers.autoscaling` | yes | no | no | no | yes | yes | no | no |
| 8 | `create jobs.batch` | yes | no | yes | no | yes | yes | no | no |
| 9 | `delete jobs.batch` | yes | no | yes | no | yes | yes | no | no |
| 10 | `delete configmaps` | yes | no | no | no | yes | yes | no | no |
| 11 | `get secrets` | no | no | no | no | yes | yes | no | no |
| 12 | `list secrets` | no | no | no | no | yes | yes | no | no |
| 13 | `create secrets` | no | no | no | no | yes | yes | no | no |
| 14 | `create persistentvolumeclaims` | no | no | no | no | yes | yes | no | no |
| 15 | `create statefulsets.apps` | no | no | no | no | yes | yes | no | no |
| 16 | `create daemonsets.apps` | no | no | no | no | yes | yes | no | no |
| 17 | `list roles.rbac.authorization.k8s.io` | no | no | no | no | no | no | yes | yes |
| 18 | `list rolebindings.rbac.authorization.k8s.io` | no | no | no | no | no | no | yes | yes |
| 19 | `create rolebindings.rbac.authorization.k8s.io` | no | no | no | no | no | no | no | no |

### Escopo de cluster

| # | verbo recurso | dev | qa | sre | auditor |
|---|---|---|---|---|---|
| 1 | `get nodes` | no | no | yes | no |
| 2 | `list persistentvolumes` | no | no | yes | no |
| 3 | `list storageclasses.storage.k8s.io` | no | no | yes | no |
| 4 | `list namespaces` | no | no | yes | no |
| 5 | `create namespaces` | no | no | no | no |
| 6 | `create clusterrolebindings.rbac.authorization.k8s.io` | no | no | no | no |
| 7 | `list pods --all-namespaces` | no | no | no | no |
| 8 | `get secrets -n kube-system` | no | no | no | no |

## Verificação dos critérios de aceite

| Critério | Resultado (linhas da matriz) |
|---|---|
| Matriz com no mínimo 14 linhas × 8 colunas, toda preenchida com saída real | 19 linhas × 8 colunas (+ 8 linhas de escopo de cluster) |
| `fiap:auditor` = `no` para todo verbo de escrita, nos dois namespaces | linhas 3 a 10, 13 a 16 e 19: todas `no` |
| `fiap:auditor` = `no` para `get secrets` nos dois namespaces | linha 11: `no` / `no` |
| `fiap:dev` = `yes` para `create pods/exec` em store-dev e `no` em store-prod | linha 3: `yes` / `no` |
| `fiap:sre` = `yes` para `get nodes` | cluster, linha 1: `yes` |
| `fiap:sre` = `no` para `create clusterrolebindings` | cluster, linha 6: `no` (e também negado ao tentar de verdade) |
| Nenhum YAML com `"*"` em verbs ou resources | `grep -cE '"\*"\|\[\*\]' rbac-modelo.yaml` retorna `0` |

Outros pontos que a matriz confirma:

- `fiap:dev` em store-prod: só leitura (linhas 1 e 2 `yes`, todo o resto `no`), sem secrets (11) e sem exec (3).
- `fiap:qa`: leitura nos dois namespaces; Job (8 e 9) e exec (3) **apenas** em store-dev.
- `fiap:sre`: controle total nos dois namespaces, inclusive secrets, PVC, StatefulSet e DaemonSet (11 a 16), mas **não** escreve RBAC (19) e **não** é cluster-admin: no escopo de cluster, `create namespaces`, `create clusterrolebindings`, `list pods --all-namespaces` e `get secrets -n kube-system` dão `no`.
- Ninguém cria `rolebindings` (linha 19). Mudança de RBAC é atribuição do administrador do cluster (ou do GitOps), justamente para impedir autoconcessão.

## Por que o perfil `auditor` NÃO usa o ClusterRole `view` como está

Inspecionando o `view` deste cluster (`kubectl get clusterrole view -o json`), ele tem dois problemas para auditoria. Primeiro, **não inclui `roles` nem `rolebindings`**: um auditor com `view` não conseguiria ver quem tem acesso a quê, que é justamente o objeto principal de uma auditoria de acesso. Segundo, o `view` é um **ClusterRole agregado** (`aggregationRule` com o label `rbac.authorization.k8s.io/aggregate-to-view: "true"`): o conteúdo dele é a soma de todo ClusterRole com esse label, e muda sozinho sempre que um operador ou chart instala um ClusterRole rotulado. Hoje são `system:aggregate-to-view` e `system:aggregated-metrics-reader`, mas qualquer `helm install` futuro pode ampliar o acesso do auditor sem ninguém revisar (e um chart mal escrito poderia até agregar verbos de escrita). Por isso o auditor recebe o `fiap-auditor`, uma lista **fechada e explícita** só com `get/list/watch`: inclui RBAC e exclui `secrets`, cuja leitura revelaria o valor (base64 não é criptografia). Ler `rolebindings` é sensível, porque revela o mapa de quem pode escalar. Por isso a permissão vem limitada aos dois namespaces da aplicação, sem `clusterrolebindings` e sem nenhum verbo de escrita, o que mantém o auditor como observador puro.
