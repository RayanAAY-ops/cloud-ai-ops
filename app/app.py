"""App Lambda: saves an item to DynamoDB.

Event: {"item_name": "Widget", "price": 9.99}
"""

import os
import uuid
from decimal import Decimal

import boto3

table = boto3.resource("dynamodb").Table(os.environ["DYNAMODB_TABLE_NAME"])


def handler(event, context):
    item = {
        "item_id": str(uuid.uuid4()),
        "item_name": event["item_name"],
        "price": Decimal(str(event["price"])),  # DynamoDB needs Decimal, not float
    }
    table.put_item(Item=item)  # fails with AccessDenied while PutItem is disabled in role.tf
    return {"item_id": item["item_id"]}
