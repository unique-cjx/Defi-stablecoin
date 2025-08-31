.PHONY: ci fmt-check build test

# Run the same sequence as .github/workflows/test.yml
ci: fmt-check build test

fmt-check:
	@echo "-> running forge fmt --check"
	FOUNDRY_PROFILE=ci forge fmt --check

build:
	@echo "-> running forge build --sizes"
	FOUNDRY_PROFILE=ci forge build --sizes

test:
	@echo "-> running forge test -vvv"
	FOUNDRY_PROFILE=ci forge test -vvv