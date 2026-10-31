# Exercício 9.1: ServiceAccount somente leitura validada com can-i

Manifesto: `monitor-rbac.yaml` (ServiceAccount `monitor-sa` + Role `leitura-store` + RoleBinding + Pod `monitor` usando a SA).
Saída bruta completa, com comando e horário: `saidas.txt`.

A Role concede apenas `get`, `list` e `watch` sobre `pods`, `services`, `endpoints`, `configmaps` e o subresource `pods/log`, somente no namespace `store-dev`.

## (a) Validação com `kubectl auth can-i` (impersonation)

Sujeito: `--as=system:serviceaccount:store-dev:monitor-sa`

| # | Comando | Resultado | Esperado |
|---|---|---|---|
| 1 | `get pods -n store-dev` | yes | yes |
| 2 | `list services -n store-dev` | yes | yes |
| 3 | `watch endpoints -n store-dev` | yes | yes |
| 4 | `get configmaps -n store-dev` | yes | yes |
| 5 | `get pods --subresource=log -n store-dev` | yes | yes |
| 6 | `list pods -n store-dev` | yes | yes |
| 7 | `get secrets -n store-dev` | **no** | no |
| 8 | `create pods -n store-dev` | **no** | no |
| 9 | `delete pods -n store-dev` | **no** | no |
| 10 | `get pods -n store-prod` | **no** | no (Role é namespaced) |

> Nota: o item 5 foi reconferido com `--subresource=log` (e não com o atalho `pods/log`, que em testes dos exercícios 9.2 e 9.3 se mostrou pouco confiável). Prova real: `kubectl logs ... --as=system:serviceaccount:store-dev:monitor-sa` retorna as linhas de log, e `can-i create pods --subresource=exec` retorna `no`.

`kubectl auth can-i --list -n store-dev --as=system:serviceaccount:store-dev:monitor-sa` mostra **apenas** os recursos concedidos. As três primeiras linhas (`self*reviews`) e as Non-Resource URLs vêm das ClusterRoles padrão `system:basic-user` / `system:discovery` / `system:public-info-viewer`, que todo usuário autenticado recebe:

```
configmaps     []  []  [get list watch]
endpoints      []  []  [get list watch]
pods/log       []  []  [get list watch]
pods           []  []  [get list watch]
services       []  []  [get list watch]
```

## (b) Token JWT

`kubectl create token monitor-sa -n store-dev --duration=1h`, payload decodificado (`cut -d. -f2 | base64 -d`):

```json
{
  "aud": ["https://kubernetes.default.svc.cluster.local"],
  "exp": 1793481634,
  "iat": 1793478034,
  "iss": "https://kubernetes.default.svc.cluster.local",
  "kubernetes.io": {
    "namespace": "store-dev",
    "serviceaccount": { "name": "monitor-sa", "uid": "9b6999c3-71fd-4697-ad46-53c228921396" }
  },
  "nbf": 1793478034,
  "sub": "system:serviceaccount:store-dev:monitor-sa"
}
```

- **sub** = `system:serviceaccount:store-dev:monitor-sa` (exatamente o sujeito do RoleBinding)
- **aud** = `https://kubernetes.default.svc.cluster.local` (o token só vale para este API server)
- **exp** = 1793481634 = `2026-10-31T21:20:34Z`, ou seja, **1 hora** após o `iat` (`20:20:34Z`), conforme `--duration=1h`. É um token *bound* e temporário, não o Secret de token permanente das versões antigas.

## (c) Chamadas à API de dentro do Pod com o token montado

O Pod `monitor` (`serviceAccountName: monitor-sa`) recebe o token projetado em `/var/run/secrets/kubernetes.io/serviceaccount/` (`ca.crt`, `namespace`, `token`).

**Listar Pods: HTTP 200**

```
curl --cacert .../ca.crt -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/store-dev/pods
HTTP 200
kind=PodList  itens=22
  cliente  Running
  monitor  Running
  redis-74cd45cd74-rcrzm  Running
  store-api-5f986f48b9-n7vsr  Running
  ...
```

**Listar Secrets: HTTP 403**

```
curl --cacert .../ca.crt -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/store-dev/secrets
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "secrets is forbidden: User \"system:serviceaccount:store-dev:monitor-sa\" cannot list resource \"secrets\" in API group \"\" in the namespace \"store-dev\"",
  "reason": "Forbidden",
  "details": { "kind": "secrets" },
  "code": 403
}
HTTP 403
```

Foi usado `--cacert` com a CA montada em vez de `-k`: a conexão é validada de verdade, sem desligar a verificação TLS.

## Critérios de aceite

- [x] `can-i --list` mostra apenas os recursos concedidos
- [x] `get secrets` e `create pods` retornam `no`
- [x] `sub` do JWT é exatamente `system:serviceaccount:store-dev:monitor-sa`
- [x] `curl` em `/api/v1/namespaces/store-dev/secrets` retorna HTTP 403 com `"reason": "Forbidden"`
