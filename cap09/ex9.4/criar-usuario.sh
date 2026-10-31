#!/usr/bin/env bash
# criar-usuario.sh <usuario> <grupo>: emite certificado via CSR do cluster e gera kubeconfig autocontido
set -euo pipefail
U=$1; G=$2; D=usuarios/$U; mkdir -p "$D"
openssl genrsa -out "$D/$U.key" 2048 2>/dev/null
openssl req -new -key "$D/$U.key" -out "$D/$U.csr" -subj "/CN=$U/O=$G"
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: $U}
spec:
  request: $(base64 < "$D/$U.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800
  usages: [client auth]
YAML
kubectl certificate approve "$U" >/dev/null
for i in 1 2 3 4 5; do C=$(kubectl get csr "$U" -o jsonpath='{.status.certificate}'); [ -n "$C" ] && break; sleep 1; done
echo "$C" | base64 -d > "$D/$U.crt"
K="$D/kubeconfig-$U.yaml"
kubectl config set-cluster cp-bara --server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" \
  --certificate-authority="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority}')" --embed-certs=true --kubeconfig="$K" >/dev/null
kubectl config set-credentials "$U" --client-certificate="$D/$U.crt" --client-key="$D/$U.key" --embed-certs=true --kubeconfig="$K" >/dev/null
kubectl config set-context "$U" --cluster=cp-bara --user="$U" --kubeconfig="$K" >/dev/null
kubectl config use-context "$U" --kubeconfig="$K" >/dev/null
openssl x509 -in "$D/$U.crt" -noout -subject
