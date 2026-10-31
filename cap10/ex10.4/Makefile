# Makefile da FIAP Store (ex 10.4). Uso: make deploy-dev | deploy-prod | scan | diff | destroy
# Cada alvo usa o contexto ATUAL do kubectl; confira com: kubectl config current-context

KUBECTL ?= kubectl
DEV      = k8s/overlays/dev
PROD     = k8s/overlays/prod
SM_CRD   = https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.80.1/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

.PHONY: help prereqs render validate deploy-dev deploy-prod deploy-all scan diff destroy

help:
	@grep -E "^[a-z-]+:.*##" $(MAKEFILE_LIST) | awk -F":.*## " "{printf \"%-12s %s\\n\", \$$1, \$$2}"

prereqs: ## instala o CRD ServiceMonitor (Prometheus Operator), exigido pelo overlay de prod
	$(KUBECTL) apply --server-side -f $(SM_CRD)

render: ## mostra o YAML final dos dois ambientes
	$(KUBECTL) kustomize $(DEV)
	@echo "---"
	$(KUBECTL) kustomize $(PROD)

validate: ## valida no API server sem aplicar (inclui admissao PSA); cria so os namespaces, pois o dry-run nao os cria
	$(KUBECTL) apply -f $(DEV)/namespace.yaml -f $(PROD)/namespace.yaml
	$(KUBECTL) apply -k $(DEV) --dry-run=server
	$(KUBECTL) apply -k $(PROD) --dry-run=server

deploy-dev: ## sobe o ambiente dev inteiro com um comando
	$(KUBECTL) apply -k $(DEV)
	$(KUBECTL) -n store-dev rollout status deploy --timeout=180s

deploy-prod: prereqs ## sobe o ambiente prod inteiro com um comando
	$(KUBECTL) apply -k $(PROD)
	$(KUBECTL) -n store-prod rollout status deploy --timeout=300s

deploy-all: deploy-dev deploy-prod ## sobe os dois ambientes

scan: ## Trivy em todas as imagens referenciadas pelos dois overlays (porta de qualidade)
	@for img in $$( { $(KUBECTL) kustomize $(DEV); $(KUBECTL) kustomize $(PROD); } | grep -E "^ +(- )?image:" | awk "{print \$$NF}" | sort -u); do \
	  echo "== $$img"; trivy image -q --scanners vuln --severity CRITICAL --ignore-unfixed --exit-code 1 $$img || exit 1; \
	done

diff: ## diferenca entre o Git e o cluster (exit 1 = ha diferenca)
	-$(KUBECTL) diff -k $(DEV)
	-$(KUBECTL) diff -k $(PROD)

destroy: ## remove os dois ambientes (namespaces inclusos)
	-$(KUBECTL) delete -k $(DEV) --ignore-not-found --wait=true
	-$(KUBECTL) delete -k $(PROD) --ignore-not-found --wait=true
