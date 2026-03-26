"""Trigger dashboard sync ECS RunTask when grafana/dashboards/ S3 objects are created."""
import json
import logging
import os
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client("ecs")

# Poll until sync task stops so failures (e.g. S3/EFS errors) surface in Lambda logs.
_MAX_WAIT_SEC = 90
_POLL_SEC = 3


def lambda_handler(event, context):
    cluster = os.environ["ECS_CLUSTER_ARN"].strip()
    task_def = os.environ["SYNC_TASK_DEFINITION"].strip()
    subnets = [s.strip() for s in os.environ["SUBNET_IDS"].split(",") if s.strip()]
    security_groups = [s.strip() for s in os.environ["SECURITY_GROUP_IDS"].split(",") if s.strip()]

    logger.info("S3 event: %s", json.dumps(event)[:4000])

    response = ecs.run_task(
        cluster=cluster,
        taskDefinition=task_def,
        launchType="EC2",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": subnets,
                "securityGroups": security_groups,
                "assignPublicIp": "DISABLED",
            }
        },
    )

    failures = response.get("failures", [])
    if failures:
        raise RuntimeError(f"RunTask failures: {failures}")

    tasks = response.get("tasks", [])
    if not tasks:
        raise RuntimeError("RunTask returned no tasks")

    task_arn = tasks[0]["taskArn"]
    logger.info("Started sync task: %s", task_arn)

    deadline = time.time() + _MAX_WAIT_SEC
    while time.time() < deadline:
        time.sleep(_POLL_SEC)
        desc = ecs.describe_tasks(cluster=cluster, tasks=[task_arn])
        if not desc.get("tasks"):
            raise RuntimeError(f"describe_tasks returned no tasks for {task_arn}")
        t = desc["tasks"][0]
        status = t.get("lastStatus")
        logger.info("task lastStatus=%s desiredStatus=%s", status, t.get("desiredStatus"))
        if status != "STOPPED":
            continue
        for c in t.get("containers", []):
            logger.info(
                "container name=%s exitCode=%s reason=%s",
                c.get("name"),
                c.get("exitCode"),
                c.get("reason"),
            )
        exit_code = None
        for c in t.get("containers", []):
            if c.get("name") == "sync-grafana":
                exit_code = c.get("exitCode")
                break
        if exit_code is None:
            exit_code = (t.get("containers") or [{}])[0].get("exitCode")
        if exit_code not in (0, None):
            raise RuntimeError(f"sync-grafana exited with code {exit_code}")
        return {"ok": True, "taskArn": task_arn}

    raise RuntimeError(f"task {task_arn} did not reach STOPPED within {_MAX_WAIT_SEC}s")
