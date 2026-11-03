"""CPU de alta resolución y estado real del grupo; desactivado en local."""

import logging
import os
import threading
import time
from functools import lru_cache

import boto3
from botocore.config import Config

from app import cpu, metadata

logger = logging.getLogger(__name__)
NAMESPACE = "Grimorios/Demo"


@lru_cache(maxsize=3)
def client(service: str):
    return boto3.session.Session().client(
        service,
        region_name=metadata.get_metadata()["region"],
        config=Config(connect_timeout=1, read_timeout=2, retries={"max_attempts": 0}),
    )


def group_name() -> str:
    return os.getenv("AUTOSCALING_GROUP_NAME", "")


class CpuPublisher:
    def __init__(self):
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None

    def start(self):
        if not group_name() or metadata.get_metadata()["source"] != "imds":
            return
        self.stop_event.clear()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=4)

    def run(self):
        # Excluir el pico de arranque de Docker de la señal de saturación.
        if self.stop_event.wait(20):
            return
        samples: list[float] = []
        member = False
        while not self.stop_event.wait(1):
            if cpu.monitor.percent is None:
                continue
            samples.append(cpu.monitor.percent)
            if len(samples) < 10:
                continue
            value = sum(samples) / len(samples)
            samples.clear()
            try:
                if not member:
                    groups = client("autoscaling").describe_auto_scaling_groups(
                        AutoScalingGroupNames=[group_name()]
                    )["AutoScalingGroups"]
                    instance_id = metadata.get_metadata()["instance_id"]
                    member = bool(groups) and any(
                        item["InstanceId"] == instance_id for item in groups[0]["Instances"]
                    )
                    if not member:
                        continue  # Los constructores de AMI no aportan CPU al grupo.
                client("cloudwatch").put_metric_data(
                    Namespace=NAMESPACE,
                    MetricData=[{
                        "MetricName": "CPUUtilization",
                        "Dimensions": [{"Name": "AutoScalingGroupName", "Value": group_name()}],
                        "Value": value,
                        "Unit": "Percent",
                        "StorageResolution": 1,
                    }],
                )
            except Exception:
                logger.warning("No se pudo publicar CPU de alta resolución", exc_info=True)


publisher = CpuPublisher()
_summary_lock = threading.Lock()
_summary_cache: tuple[float, dict] | None = None


def summary() -> dict:
    global _summary_cache
    if not group_name():
        return {"status": "disabled", "instances": []}
    with _summary_lock:
        if _summary_cache and time.monotonic() - _summary_cache[0] < 3:
            return _summary_cache[1]
        groups = client("autoscaling").describe_auto_scaling_groups(
            AutoScalingGroupNames=[group_name()]
        )["AutoScalingGroups"]
        if not groups:
            raise RuntimeError("No existe el grupo configurado")
        group = groups[0]
        targets = client("elbv2").describe_target_health(
            TargetGroupArn=os.environ["TARGET_GROUP_ARN"]
        )["TargetHealthDescriptions"]
        health = {item["Target"]["Id"]: item["TargetHealth"]["State"] for item in targets}
        instances = []
        for item in group["Instances"]:
            lifecycle = item["LifecycleState"]
            state = "deploying"
            if lifecycle.startswith("Terminating") or health.get(item["InstanceId"]) == "draining":
                state = "terminating"
            elif lifecycle == "InService" and health.get(item["InstanceId"]) == "healthy":
                state = "ready"
            instances.append({
                "instance_id": item["InstanceId"],
                "availability_zone": item["AvailabilityZone"],
                "state": state,
            })
        ready = sum(item["state"] == "ready" for item in instances)
        pending = sum(item["state"] == "deploying" for item in instances)
        active = sum(item["state"] != "terminating" for item in instances)
        result = {
            "status": "ok",
            "desired": group["DesiredCapacity"],
            "minimum": group["MinSize"],
            "maximum": group["MaxSize"],
            "ready": ready,
            "deploying": pending + max(0, group["DesiredCapacity"] - active),
            "instances": instances,
        }
        _summary_cache = (time.monotonic(), result)
        return result
