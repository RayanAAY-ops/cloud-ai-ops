trigger_and_watch:
	./invoke.sh                              # app fails → errors in its logs
	cd terraform && make alarm-test ENV=dev  # OK → ALARM → agent

	# in two other terminals:
	aws logs tail /aws/lambda/cloudops-ai-app-dev-agent --follow
	aws logs tail /aws/lambda/cloudops-ai-app-dev-pr --follow
