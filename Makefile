CLUSTER   ?= wordpress
NAMESPACE ?= wordpress
RELEASE   ?= wordpress

# Every command is pinned to the kind cluster, so a different current kubectl
# context can never receive the install.
CONTEXT := kind-$(CLUSTER)
KUBECTL := kubectl --context $(CONTEXT) --namespace $(NAMESPACE)
HELM    := helm --kube-context $(CONTEXT) --namespace $(NAMESPACE)

.DEFAULT_GOAL := help
.PHONY: help lint render cluster secret install test port-forward uninstall down

help: ## Show this list
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

lint: ## Lint the chart with the default values and the ingress example
	helm lint charts/wordpress
	helm lint charts/wordpress -f examples/values-ingress.yaml

render: ## Render the chart to rendered.yaml
	helm template $(RELEASE) charts/wordpress --namespace $(NAMESPACE) > rendered.yaml

cluster: ## Create the kind cluster if it does not exist
	@kind get clusters | grep -qx '$(CLUSTER)' || kind create cluster --name $(CLUSTER)

secret: cluster ## Create the namespace and the database Secret with random passwords
	@kubectl --context $(CONTEXT) get namespace $(NAMESPACE) >/dev/null 2>&1 || \
		kubectl --context $(CONTEXT) create namespace $(NAMESPACE)
	@$(KUBECTL) get secret wordpress-db >/dev/null 2>&1 || \
		$(KUBECTL) create secret generic wordpress-db \
			--from-literal=mysql-root-password="$$(openssl rand -hex 16)" \
			--from-literal=mysql-password="$$(openssl rand -hex 16)"

install: secret ## Install or upgrade the chart in the kind cluster
	$(HELM) upgrade --install $(RELEASE) charts/wordpress --wait --timeout 10m

test: ## Run the Helm test that requests the login page
	$(HELM) test $(RELEASE) --timeout 5m --logs

port-forward: ## Open WordPress on http://localhost:8080
	$(KUBECTL) port-forward svc/$(RELEASE) 8080:80

uninstall: ## Remove the release (the volume claims stay)
	$(HELM) uninstall $(RELEASE)

down: ## Delete the kind cluster and everything in it
	kind delete cluster --name $(CLUSTER)
