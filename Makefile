.PHONY: build test run bundle release clean

build:        ## Debug build
	swift build

test:         ## Run ConsaiCore unit tests
	swift test

run: bundle   ## Build + bundle + launch Consai.app
	open Consai.app

bundle:       ## Assemble a debug Consai.app
	scripts/bundle.sh debug

release:      ## Assemble a release Consai.app (ad-hoc signed)
	scripts/bundle.sh release

clean:
	rm -rf .build Consai.app
