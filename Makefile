# Developer commands (infra commands are in terraform/Makefile)
#
#   make setup              # once: venv with test tools + git pre-commit hook
#   make test               # run the tests
#   make check              # run every pre-commit hook on every file
#   make trigger_and_watch  # break the app, fire the alarm, then follow the logs

.PHONY: setup test check trigger_and_watch

setup:
	python3 -m venv .venv
	.venv/bin/pip install -q -r requirements-dev.txt
	.venv/bin/pre-commit install

check:
	.venv/bin/pre-commit run --all-files

trigger_and_watch:
	./invoke.sh                              # app fails → errors in its logs
	cd terraform && make alarm-test ENV=dev  # OK → ALARM → agent

	# in two other terminals:
	aws logs tail /aws/lambda/cloudops-ai-app-dev-agent --follow
	aws logs tail /aws/lambda/cloudops-ai-app-dev-pr --follow
