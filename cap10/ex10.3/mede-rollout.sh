#!/usr/bin/env bash
# mede-rollout.sh <manifesto> <imagem-nova> <rotulo>
# 1) aplica o manifesto e espera estabilizar; 2) liga a carga continua contra o Service;
# 3) dispara kubectl set image; 4) espera o rollout terminar + 10s; 5) conta OK/FALHA.
set -u
export LC_ALL=C
M=$1; NOVA=$2; R=$3; NS=store-rollout; OUT=evidencias/carga-$R.log
kubectl apply -f "$M" >/dev/null
kubectl rollout status deploy/store-api -n $NS --timeout=300s >/dev/null
sleep 8
# carga: wget com timeout de 2s, ate existir /tmp/parar
kubectl exec -n $NS carga -- rm -f /tmp/parar
kubectl exec -n $NS carga -- sh -c 'while [ ! -f /tmp/parar ]; do if wget -q -O /dev/null -T 2 http://store-api/produtos 2>/dev/null; then echo "$(date +%T) OK"; else echo "$(date +%T) FALHA"; fi; done' > "$OUT" &
LP=$!
sleep 5
T0=$(date +%s)
kubectl set image deploy/store-api store-api=store-api:$NOVA -n $NS >/dev/null
if [ "$R" = "e-final-lifespan" ]; then
  sleep 6
  P=$(kubectl get pods -n $NS -l app=store-api -o json | jq -r '.items[] | select(.metadata.deletionTimestamp!=null) | .metadata.name' | head -1)
  { echo "\$ kubectl describe pod $P -n $NS   (Pod em Terminating durante o rollout)"; kubectl describe pod "$P" -n $NS; echo; echo "\$ kubectl get pod $P -o jsonpath lifecycle/grace"; kubectl get pod "$P" -n $NS -o jsonpath='{.spec.containers[0].lifecycle}{"\n"}terminationGracePeriodSeconds={.spec.terminationGracePeriodSeconds}{"\n"}deletionTimestamp={.metadata.deletionTimestamp}{"\n"}'; } > evidencias/describe-pod-terminating.txt 2>&1
fi
kubectl rollout status deploy/store-api -n $NS --timeout=300s >/dev/null
T1=$(date +%s)
# espera TODOS os Pods antigos sairem de Terminating (preStop + grace), e so entao para a carga
while kubectl get pods -n $NS -l app=store-api -o json | jq -e '[.items[] | select(.metadata.deletionTimestamp!=null)] | length > 0' >/dev/null; do sleep 1; done
T2=$(date +%s)
sleep 5
kubectl exec -n $NS carga -- touch /tmp/parar; sleep 3; kill $LP 2>/dev/null; wait $LP 2>/dev/null
TOT=$(grep -cE 'OK|FALHA' "$OUT"); F=$(grep -c FALHA "$OUT")
MAXOK=$(awk '{if($2=="OK"){c++; if(c>m)m=c} else c=0} END{print m+0}' "$OUT")
printf "%-20s rollout=%3ss ate_ultimo_pod_antigo_sumir=%3ss total=%5d falhas=%4d por100=%6.2f maior_sequencia_OK=%d\n" "$R" "$((T1-T0))" "$((T2-T0))" "$TOT" "$F" "$(echo "scale=2; $F*100/$TOT" | bc)" "$MAXOK" | tee -a evidencias/resumo.txt
