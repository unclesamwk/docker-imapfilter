IMAGE ?= anyone/imapfilter
TAG ?= latest

.DEFAULT_GOAL := help
.PHONY: help lint build test run run-once

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  make lint      # shell syntax checks' \
	  '  make build     # build container image' \
	  '  make test      # run lint + build + smoke test' \
	  '  make run       # run scheduled container' \
	  '  make run-once  # run one-shot container'

lint:
	bash -n run.sh
	bash -n healthcheck.sh

build:
	docker build -t $(IMAGE):$(TAG) .

test: lint build
	@set -eu; \
	output_file=$$(mktemp); \
	set +e; docker run --rm $(IMAGE):$(TAG) >$$output_file 2>&1; rc=$$?; set -e; \
	test $$rc -eq 1; \
	grep -q 'Config not found' $$output_file; \
	rm -f $$output_file

run:
	docker run -d \
		--name imapfilter \
		-v $(HOME)/.config/imapfilter:/home/imap/.imapfilter:ro \
		$(IMAGE):$(TAG)

run-once:
	docker run --rm \
		-e IMAPFILTER_ONCE=true \
		-v $(HOME)/.config/imapfilter:/home/imap/.imapfilter:ro \
		$(IMAGE):$(TAG)
