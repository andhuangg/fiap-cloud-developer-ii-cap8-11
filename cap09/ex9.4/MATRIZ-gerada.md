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
