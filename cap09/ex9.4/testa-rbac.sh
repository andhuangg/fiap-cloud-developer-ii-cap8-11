#!/usr/bin/env bash
# testa-rbac.sh: gera a matriz de permissoes a partir da saida REAL de kubectl auth can-i.
# Uso: ./testa-rbac.sh > MATRIZ-gerada.md
# Para cada perfil usa um usuario ficticio + o grupo do perfil (--as / --as-group).
# Subresources (pods/log, pods/exec) sao testados com --subresource, porque o atalho
# "pods/exec" do can-i se mostrou nao confiavel no kubectl v1.33 (ver ex 9.2 e 9.3).
set -euo pipefail

PERFIS=(dev qa sre auditor)
NAMESPACES=(store-dev store-prod)

# "verbo recurso[/subresource]"
CHECKS=(
  "get pods"
  "get pods/log"
  "create pods/exec"
  "delete pods"
  "create deployments.apps"
  "delete deployments.apps"
  "patch horizontalpodautoscalers.autoscaling"
  "create jobs.batch"
  "delete jobs.batch"
  "delete configmaps"
  "get secrets"
  "list secrets"
  "create secrets"
  "create persistentvolumeclaims"
  "create statefulsets.apps"
  "create daemonsets.apps"
  "list roles.rbac.authorization.k8s.io"
  "list rolebindings.rbac.authorization.k8s.io"
  "create rolebindings.rbac.authorization.k8s.io"
)
CLUSTER_CHECKS=(
  "get nodes"
  "list persistentvolumes"
  "list storageclasses.storage.k8s.io"
  "list namespaces"
  "create namespaces"
  "create clusterrolebindings.rbac.authorization.k8s.io"
  "list pods --all-namespaces"
  "get secrets -n kube-system"
)

canI() { # verbo recurso[/sub] [args extras...]
  local verb=$1 res=$2; shift 2
  local sub=""
  if [[ $res == */* ]]; then sub="--subresource=${res#*/}"; res=${res%%/*}; fi
  kubectl auth can-i "$verb" "$res" $sub "$@" 2>/dev/null || true
}

echo "Gerada em $(date '+%Y-%m-%d %H:%M:%S %Z') a partir de \`kubectl auth can-i --as=teste.<perfil> --as-group=fiap:<perfil>\`"
echo "Contexto: $(kubectl config current-context)"
echo
echo "### Recursos com namespace"
echo
printf "| # | verbo recurso |"; for g in "${PERFIS[@]}"; do for ns in "${NAMESPACES[@]}"; do printf " %s @ %s |" "$g" "${ns#store-}"; done; done; echo
printf "|---|---|"; for g in "${PERFIS[@]}"; do for ns in "${NAMESPACES[@]}"; do printf -- "---|"; done; done; echo
i=0
for c in "${CHECKS[@]}"; do
  i=$((i+1)); read -r verb res <<<"$c"
  printf "| %d | \`%s %s\` |" "$i" "$verb" "$res"
  for g in "${PERFIS[@]}"; do for ns in "${NAMESPACES[@]}"; do
    printf " %s |" "$(canI "$verb" "$res" -n "$ns" --as="teste.$g" --as-group="fiap:$g")"
  done; done; echo
done
echo
echo "### Escopo de cluster"
echo
printf "| # | verbo recurso |"; for g in "${PERFIS[@]}"; do printf " %s |" "$g"; done; echo
printf "|---|---|"; for g in "${PERFIS[@]}"; do printf -- "---|"; done; echo
i=0
for c in "${CLUSTER_CHECKS[@]}"; do
  i=$((i+1)); read -r verb res extra <<<"$c"
  printf "| %d | \`%s %s%s\` |" "$i" "$verb" "$res" "${extra:+ $extra}"
  for g in "${PERFIS[@]}"; do
    printf " %s |" "$(canI "$verb" "$res" $extra --as="teste.$g" --as-group="fiap:$g")"
  done; echo
done
