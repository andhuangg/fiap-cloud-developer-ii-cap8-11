#!/bin/bash
source ~/Downloads/cp-bara/.lab/env.sh; cd $CP/cap08/ex8.2; D=evidencias
snap() { ev $D/$1 "kubectl get cronjob,jobs,pods -n store-dev | grep -E 'NAME|sincroniza'; echo -n 'jobs ativos (.status.active): '; kubectl get cronjob sincroniza-catalogo -n store-dev -o jsonpath='{.status.active[*].name}'; echo"; }
ev $D/01-allow.txt kubectl apply -f catalogo-secret.yaml -f sincroniza-cronjob-allow.yaml
T0=$(date +%s)
patched=0
# fase Allow: 12 minutos, amostra a cada 30s
while [ $(( $(date +%s) - T0 )) -lt 720 ]; do
  snap 01-allow.txt >/dev/null
  # patch do secret durante uma execucao ativa (uma vez), ~2 min apos o primeiro Job iniciar
  P=$(kubectl get pods -n store-dev -l job-name --field-selector=status.phase=Running -o name | grep sincroniza | head -1)
  if [ $patched -eq 0 ] && [ -n "$P" ]; then
    age=$(( $(date +%s) - $(date -j -f %Y-%m-%dT%H:%M:%SZ "$(kubectl get $P -n store-dev -o jsonpath='{.status.startTime}')" +%s) + 10800 ))
    if [ $age -gt 60 ]; then
      F=$D/03-secret-env-x-volume.txt
      ev $F "echo POD=$P"
      ev $F kubectl exec -n store-dev $P -- printenv API_TOKEN
      ev $F kubectl exec -n store-dev $P -- cat /etc/catalogo/token
      ev $F kubectl exec -n store-dev $P -- ls -lL /etc/catalogo/token
      ev $F "kubectl patch secret catalogo-secret -n store-dev -p '{\"stringData\":{\"API_TOKEN\":\"token-v2-rotacionado\"}}'"
      ev $F "kubectl get secret catalogo-secret -n store-dev -o jsonpath='{.data.API_TOKEN}' | base64 -d; echo"
      sleep 90
      ev $F "echo mesmo pod apos 90s: $P"
      ev $F kubectl exec -n store-dev $P -- printenv API_TOKEN
      ev $F kubectl exec -n store-dev $P -- cat /etc/catalogo/token
      patched=1
    fi
  fi
  sleep 30
done
snap 01-allow.txt >/dev/null
ev $D/01-allow.txt "kubectl get events -n store-dev --field-selector involvedObject.name=sincroniza-catalogo --sort-by=.lastTimestamp"
# fase Forbid: 12 minutos
ev $D/02-forbid.txt kubectl apply -f sincroniza-cronjob-forbid.yaml
T1=$(date +%s)
while [ $(( $(date +%s) - T1 )) -lt 720 ]; do snap 02-forbid.txt >/dev/null; sleep 30; done
snap 02-forbid.txt >/dev/null
ev $D/02-forbid.txt kubectl describe cronjob sincroniza-catalogo -n store-dev
ev $D/02-forbid.txt "kubectl get events -n store-dev --field-selector involvedObject.name=sincroniza-catalogo --sort-by=.lastTimestamp"
kubectl patch cronjob sincroniza-catalogo -n store-dev -p '{"spec":{"suspend":true}}'
echo FIM-8.2
