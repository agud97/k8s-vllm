.PHONY: help bootstrap deploy validate smoke-test validate-static

help:
	@./bootstrap/cli.sh help

bootstrap:
	@./bootstrap/cli.sh bootstrap

deploy:
	@./bootstrap/cli.sh deploy

validate:
	@./bootstrap/cli.sh validate

validate-static:
	@./tests/static/validate-static.sh

smoke-test:
	@./tests/smoke-test.sh
