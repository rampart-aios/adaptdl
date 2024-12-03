# Set ADAPTDL_DEV_REPO to use an external docker registry.
# Set ADAPTDL_DEV_REPO_CREDS to the name of registry secret.
RELEASE_NAME = adaptdl
DEV_REPO_PORT = 32000
DEV_REPO = $(or $(ADAPTDL_DEV_REPO),localhost:$(DEV_REPO_PORT)/adaptdl-sched)
IMAGE_TAG = $(shell docker run --rm -v `pwd`:/git-semver ghcr.io/mdomke/git-semver | sed 's/+/-/')
VERSION = $(shell echo $(IMAGE_TAG) | sed -e 's/^v//' -e 's/dev\./dev/')
IMAGE_DIGEST = $(shell docker images --format='{{.Repository}}:{{.Tag}} {{.Digest}}' | \
		grep '^$(DEV_REPO):$(IMAGE_TAG) ' | awk '{ printf $$2 }')
NAMESPACE = $(or $(shell kubectl config view --minify -o 'jsonpath={..namespace}'),default)

.values.yaml:
	@awk '{print "#" $$0}' helm/adaptdl-sched/values.yaml > .values.yaml

registry:
	helm status adaptdl-registry || \
	helm install adaptdl-registry stable/docker-registry \
		--set fullnameOverride=adaptdl-registry \
		--set service.type=NodePort \
		--set service.nodePort=$(DEV_REPO_PORT)

build:
	docker build -f sched/Dockerfile . -t $(DEV_REPO):$(IMAGE_TAG) --build-arg ADAPTDL_VERSION=$(VERSION)

check-requirements:
	@python3 cli/check_requirements.py

push: check-requirements registry build
	docker push $(DEV_REPO):$(IMAGE_TAG)

deploy: push .values.yaml
	helm dep up helm/adaptdl-sched
	helm upgrade $(RELEASE_NAME) helm/adaptdl-sched --install --wait \
	$(and $(ADAPTDL_DEV_REPO_CREDS),--set 'image.pullSecrets[0].name=$(ADAPTDL_DEV_REPO_CREDS)') \
		--set image.repository=$(DEV_REPO) \
		--set image.digest=$(IMAGE_DIGEST) \
		--values .values.yaml

delete:
	helm delete $(RELEASE_NAME) || \
	helm delete adaptdl-registry

config: .values.yaml
	$(or $(shell git config --get core.editor),editor) .values.yaml

.PHONY: registry build push deploy delete config
