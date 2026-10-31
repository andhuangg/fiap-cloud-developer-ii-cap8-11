# Exercício 11.2: Promoção de dev para prod por PR com Kustomize overlays

- **Config repo:** https://github.com/andhuangg/fiap-store-config
- **PR de promoção:** https://github.com/andhuangg/fiap-store-config/pull/1
- **Evidências:** `saidas.txt` (comandos com horário), `print-pr-promocao-diff.png` (diff do PR), `print-argocd-apps.png` (Applications do projeto)
- **Cópias para conferência:** `kustomization-dev.yaml`, `kustomization-prod.yaml`, `appproject-fiap-store.yaml`, `app-kube-system-rejeitada.yaml`

## Árvore do repositório

```
.
├── apps
│   ├── project.yaml          # AppProject fiap-store
│   ├── store-dev.yaml        # Application fiap-store-dev  (project: fiap-store)
│   └── store-prod.yaml       # Application fiap-store-prod (project: fiap-store)
├── base
│   ├── kustomization.yaml
│   ├── store-api-deployment.yaml
│   └── store-api-service.yaml
├── overlays
│   ├── dev
│   │   └── kustomization.yaml
│   └── prod
│       ├── kustomization.yaml
│       ├── patch-prod.yaml   # APP_ENV=prod, recursos maiores, terminationGracePeriodSeconds: 60
│       └── pdb.yaml          # PodDisruptionBudget minAvailable: 2
└── README.md
```

O `overlays/prod` reaproveita a base com `resources: [../../base]`, **sem copiar** o Deployment. As diferenças de prod são:
- namespace `store-prod`;
- 4 réplicas;
- `APP_ENV=prod`;
- requests de 100m / 128Mi e limit de 256Mi;
- PDB `minAvailable: 2`;
- grace period de 60 s.

## AppProject `fiap-store`

```yaml
spec:
  sourceRepos:
    - https://github.com/andhuangg/fiap-store-config.git      # apenas este repo
  destinations:
    - {server: https://kubernetes.default.svc, namespace: store-dev}
    - {server: https://kubernetes.default.svc, namespace: store-prod}
  clusterResourceWhitelist:
    - {group: "", kind: Namespace}                            # de cluster, só Namespace
```

## Fluxo de release

1. **Publicar 1.1:** tag `v1.1` no app repo. O CI testou, escaneou, publicou e assinou `ghcr.io/andhuangg/fiap-store-api:1.1` (multi-arch).
2. **Dev, commit direto:** `8bc5cfc dev: store-api 1.1`. Dev reconciliou: `Synced to main (8bc5cfc)`, imagem `:1.1`, e `/versao` retornou `{"versao":"1.1"}`.
3. **Prod, por PR:** branch `promove/prod-1.1`, gerada com `kustomize edit set image ...:1.1` em `overlays/prod`. Revisão com `gh pr diff` e merge (`3474f4b`). Prod reconciliou: `Synced to main (3474f4b)`, 4/4 Pods em `:1.1`, e `/info` retornou `"env":"prod"`.

## Diff exato do PR de promoção

```diff
diff --git a/overlays/prod/kustomization.yaml b/overlays/prod/kustomization.yaml
@@ -10,6 +10,6 @@ replicas:
 images:
 - name: ghcr.io/andhuangg/fiap-store-api
   newName: ghcr.io/andhuangg/fiap-store-api
-  newTag: "1.0"
+  newTag: "1.1"
 patches:
 - path: patch-prod.yaml
```

`additions=1 deletions=1 changedFiles=1`

**Detalhe que fez diferença.** A primeira tentativa com `kustomize edit set image` gerou **15 linhas** de diff, porque o comando reescreve o arquivo inteiro no formato canônico (indentação de listas, ordem das chaves, remoção de comentários). Isso estouraria o limite de 2 linhas. A correção foi um commit separado na `main` (`be74739`) normalizando os dois `kustomization.yaml` para o formato do kustomize. A partir daí, todo bump, inclusive os do CI no ex. 11.4, vira um diff de exatamente 1 linha.

## Os dois ambientes com imagens diferentes

Os ReplicaSets guardam quando cada imagem entrou no ar em cada namespace:

```
NAMESPACE    REPLICASET             IMAGEM                                 CRIADO_UTC
store-dev    store-api-7b88c88757   ghcr.io/andhuangg/fiap-store-api:1.0   21:07:20
store-dev    store-api-9c76d975b    ghcr.io/andhuangg/fiap-store-api:1.1   21:27:55   <- dev em 1.1
store-prod   store-api-5d656cd9c7   ghcr.io/andhuangg/fiap-store-api:1.0   21:27:41   <- prod em 1.0
store-prod   store-api-6b6cdd4488   ghcr.io/andhuangg/fiap-store-api:1.1   21:29:04   <- prod em 1.1 após o merge
```

Entre 21:27:55 e 21:29:04 UTC, dev rodou `1.1` enquanto prod rodava `1.0`: é exatamente o período de revisão do PR. O Argo confirma pelas revisões do Git:

```
argocd app manifests fiap-store-prod --revision be74739 | grep image:   ->  ...fiap-store-api:1.0
argocd app manifests fiap-store-prod --revision 3474f4b | grep image:   ->  ...fiap-store-api:1.1
```

(Após o merge os dois convergem para `1.1`, como esperado. No ex. 11.4 o CI volta a colocar dev à frente de prod.)

## `kubectl get deploy,pdb` e `argocd app list`

```
store-dev:   deployment.apps/store-api   4/4   (sem PDB)
store-prod:  deployment.apps/store-api   4/4
             poddisruptionbudget.policy/store-api   MIN AVAILABLE 2   ALLOWED DISRUPTIONS 2

NAME                    NAMESPACE   PROJECT     STATUS  HEALTH   PATH
argocd/fiap-store-dev   store-dev   fiap-store  Synced  Healthy  overlays/dev
argocd/fiap-store-prod  store-prod  fiap-store  Synced  Healthy  overlays/prod
```

## Application apontando para `kube-system`: rejeitada

```
Conditions:
  Message: application destination server 'https://kubernetes.default.svc' and namespace 'kube-system'
           do not match any of the allowed destinations in project 'fiap-store'
  Type:    InvalidSpecError
$ kubectl get pods -n kube-system -l app=store-api
No resources found in kube-system namespace.
```

O objeto `Application` chega a ser criado (o AppProject não é um admission webhook), mas o Argo **recusa sincronizar** e nada é aplicado. A Application de teste foi removida em seguida.

## Critérios de aceite

- [x] Diff do PR de promoção com no máximo 2 linhas alteradas: 1 inserção e 1 remoção
- [x] Dois ambientes coexistindo com imagens diferentes, comprovado pelos ReplicaSets e pelos manifests por revisão
- [x] As duas Applications com `PROJECT: fiap-store`
- [x] Application para `kube-system` rejeitada pelo AppProject (`InvalidSpecError`)
