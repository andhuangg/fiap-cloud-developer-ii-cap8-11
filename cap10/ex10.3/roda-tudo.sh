#!/usr/bin/env bash
source ~/Downloads/cp-bara/.lab/env.sh; cd $CP/cap10/ex10.3
: > evidencias/resumo.txt
kubectl create ns store-rollout --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f manifestos/carga.yaml >/dev/null; kubectl wait --for=condition=ready pod/carga -n store-rollout --timeout=120s >/dev/null
./mede-rollout.sh manifestos/0-quebrado.yaml          shell-b    0-quebrado
./mede-rollout.sh manifestos/a-readiness.yaml         shell-b    a-readiness
./mede-rollout.sh manifestos/b-prestop.yaml           shell-b    b-prestop
./mede-rollout.sh manifestos/c-exec.yaml              exec-b     c-exec
./mede-rollout.sh manifestos/d-maxunavailable0.yaml   exec-b     d-maxunavailable0
./mede-rollout.sh manifestos/e-final-lifespan.yaml    lifespan-b e-final-lifespan
# prova do PID 1: shell form x exec form dentro do Pod (python slim nao tem ps; /proc/1/cmdline e equivalente)
{ for img in shell-a exec-a; do kubectl run pid1-$img -n store-rollout --image=store-api:$img --restart=Never >/dev/null; done; sleep 8
  for img in shell-a exec-a; do echo "\$ kubectl exec pid1-$img -- cat /proc/1/cmdline"; kubectl exec -n store-rollout pid1-$img -- sh -c 'cat /proc/1/cmdline | tr "\0" " "; echo'; done
  for img in shell-a exec-a; do s=$(date +%s); kubectl delete pod pid1-$img -n store-rollout --grace-period=20 >/dev/null; echo "kubectl delete pod pid1-$img (grace 20s) levou $(( $(date +%s)-s ))s"; done; } > evidencias/pid1.txt 2>&1
echo FIM-10.3
