import json
import os

import boto3

_endpoint = os.environ.get("S3_ENDPOINT") or None
s3 = boto3.client("s3", endpoint_url=_endpoint)


def handler(event, context):
    try:
        obj = s3.get_object(Bucket=os.environ["BUCKET"], Key=os.environ["KEY"])
        data = json.loads(obj["Body"].read())
        body = {"status": "ok", "source": "s3", "data": data}
        status = 200
    except Exception as e:
        body = {"status": "error", "message": str(e)}
        status = 500

    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }