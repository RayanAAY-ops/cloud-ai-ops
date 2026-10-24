"""Settings (from Terraform env vars) and AWS clients, shared by every module."""

import os

import boto3

APP_FUNCTION = os.environ["APP_FUNCTION"]
APP_LOG_GROUP = os.environ["APP_LOG_GROUP"]
APP_ROLE_NAME = os.environ["APP_ROLE_NAME"]
APP_ROLE_ARN = os.environ["APP_ROLE_ARN"]
APP_TABLE_ARN = os.environ["APP_TABLE_ARN"]
MODEL_ID = os.environ["MODEL_ID"]
PR_FUNCTION = os.environ["PR_FUNCTION"]

logs = boto3.client("logs")
cloudwatch = boto3.client("cloudwatch")
lambda_ = boto3.client("lambda")
iam = boto3.client("iam")
cloudtrail = boto3.client("cloudtrail")
incidents_table = boto3.resource("dynamodb").Table(os.environ["INCIDENTS_TABLE"])
