# Exercício 10.1: Endurecimento com securityContext e Pod Security Admission

Arquivos: `namespaces.yaml` (store-seguro `restricted` e store-legado `baseline`), `store-api-restrito.yaml` e `pod-privilegiado.yaml`.
Saída completa, com comando e horário: `saidas.txt`. minikube `cp-bara`, Kubernetes v1.33.1.

## Namespace `restricted`, com versão fixada

```
$ kubectl get ns store-seguro --show-labels
store-seguro   Active   kubernetes.io/metadata.name=store-seguro,
  pod-security.kubernetes.io/audit-version=v1.33,   pod-security.kubernetes.io/audit=restricted,
  pod-security.kubernetes.io/enforce-version=v1.33, pod-security.kubernetes.io/enforce=restricted,
  pod-security.kubernetes.io/warn-version=v1.33,    pod-security.kubernetes.io/warn=restricted
```

`enforce-version` fixo em `v1.33` (versão do cluster). Assim um upgrade do cluster não muda as regras sem revisão.

## `store-api` endurecida rodando

O `store-api-restrito.yaml` tem: no nível do Pod, `runAsNonRoot: true`, `runAsUser: 65532`, `fsGroup: 65532` e `seccompProfile: RuntimeDefault`; no nível do container, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true` e `capabilities.drop: ["ALL"]`; e um `emptyDir` em `/tmp`. Extras: `automountServiceAccountToken: false`, requests/limits e probes.

```
$ kubectl get pods -n store-seguro -o wide
store-api-77c7db65f-nhb4b   1/1   Running   0   13s   10.244.0.64   cp-bara
store-api-77c7db65f-xwwj4   1/1   Running   0   13s   10.244.0.63   cp-bara

$ kubectl exec -n store-seguro deploy/store-api -- id
uid=65532 gid=65532 groups=65532
```

Provas extras de que o endurecimento está ativo de fato:

```
touch /app/x   -> touch: cannot touch '/app/x': Read-only file system
touch /tmp/ok  -> -rw-r--r-- 1 65532 65532 ... /tmp/ok        (emptyDir gravável)
/proc/1/status -> CapEff: 0000000000000000   (nenhuma capability)
                  NoNewPrivs: 1               (allowPrivilegeEscalation=false)
                  Seccomp: 2                  (filtro seccomp ativo)
```

## Pod privilegiado no namespace `restricted`: rejeitado

```
$ kubectl apply -f pod-privilegiado.yaml -n store-seguro
Error from server (Forbidden): error when creating "pod-privilegiado.yaml": pods "pod-privilegiado" is forbidden: violates PodSecurity "restricted:v1.33": privileged (container "root" must not set securityContext.privileged=true), allowPrivilegeEscalation != false (container "root" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "root" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "root" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "root" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

**5 violações**: `privileged`, `allowPrivilegeEscalation`, `unrestricted capabilities`, `runAsNonRoot` e `seccompProfile`.

## O mesmo Pod no namespace `baseline`: também rejeitado, por menos motivos

```
$ kubectl apply -f pod-privilegiado.yaml -n store-legado
Error from server (Forbidden): error when creating "pod-privilegiado.yaml": pods "pod-privilegiado" is forbidden: violates PodSecurity "baseline:v1.33": privileged (container "root" must not set securityContext.privileged=true)
```

Teste de controle: o mesmo Pod **sem** `privileged: true` (ainda rodando como root, sem drop de capabilities e sem seccomp) é **aceito** no `store-legado` (`pod/pod-root-sem-privilegio created`), mas **rejeitado** no `store-seguro` com as 4 violações restantes.

## Comparação entre os dois namespaces

O Pod privilegiado foi rejeitado nos dois namespaces, mas por razões de natureza diferente. O perfil **baseline** só bloqueia escaladas *conhecidas* de privilégio (`privileged`, `hostNetwork`/`hostPID`/`hostIPC`, `hostPath`, capabilities perigosas como `SYS_ADMIN`, `hostPort`). Por isso apontou uma única violação, `privileged=true`, porque um container privilegiado tem acesso praticamente total ao node. Fora isso, o baseline é permissivo: o teste de controle mostrou que um container rodando **como root**, com as capabilities padrão e sem seccomp, é aceito no `store-legado`. O perfil **restricted** inverte a lógica: além de proibir o que o baseline proíbe, ele **exige** que o Pod declare ativamente o endurecimento (`runAsNonRoot`, `allowPrivilegeEscalation: false`, `drop: ["ALL"]`, `seccompProfile`). Por isso listou 5 violações, e mesmo o Pod sem `privileged` continuou barrado por 4. Na prática, o baseline serve de piso para workloads legadas que ainda rodam como root, e o restricted é o alvo para aplicações como a `store-api`, que comprovadamente roda com UID 65532, sem capabilities, com rootfs somente leitura e com seccomp.

## Critérios de aceite

- [x] 2 Pods da `store-api` em `Running 1/1` no namespace `restricted`
- [x] `id` retorna `uid=65532`
- [x] Pod privilegiado rejeitado com `Forbidden ... violates PodSecurity "restricted:v1.33"` e 5 violações (mínimo 4)
- [x] Mesmo Pod também rejeitado no `baseline` (1 violação, `privileged`), com a diferença explicada
