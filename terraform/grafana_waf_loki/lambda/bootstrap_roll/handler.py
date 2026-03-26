"""Force new ECS deployment when bootstrap S3 objects change (sync on next task start)."""
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client("ecs")


def lambda_handler(event, context):
    cluster = os.environ.get("ECS_CLUSTER_ARN", "").strip()
    services_raw = os.environ.get("ECS_SERVICE_NAMES", "").strip()
    services = [s.strip() for s in services_raw.split(",") if s.strip()]
    if not cluster or not services:
        raise RuntimeError("ECS_CLUSTER_ARN and ECS_SERVICE_NAMES must be set")

    logger.info("S3 event: %s", json.dumps(event)[:8000])
    for service in services:
        ecs.update_service(
            cluster=cluster,
            service=service,
            forceNewDeployment=True,
        )
        logger.info("Triggered forceNewDeployment for service=%s", service)
    return {"ok": True, "services": services}
