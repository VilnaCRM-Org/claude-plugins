# Service-owned targets, kept out of the template-synced Makefile, which reads this file with
# `-include make/service.mk`. A target defined here with a `##` help text is a service target.
.PHONY: load-tests

load-tests: ## Run every load scenario with all four profiles
	$(REQUIRE_DOCKER)
	$(STUB)
