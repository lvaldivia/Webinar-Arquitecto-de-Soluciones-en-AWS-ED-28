"""Un servidor InService aún no está listo si el ALB sigue comprobándolo."""

from app import scaling


def test_scaling_tracks_pending_slots_and_target_health(client, monkeypatch):
    monkeypatch.setenv("AUTOSCALING_GROUP_NAME", "demo-asg")
    monkeypatch.setenv("TARGET_GROUP_ARN", "demo-targets")
    monkeypatch.setattr(scaling, "_summary_cache", None)

    class Aws:
        def describe_auto_scaling_groups(self, **kwargs):
            return {"AutoScalingGroups": [{
                "DesiredCapacity": 4, "MinSize": 2, "MaxSize": 4,
                "Instances": [
                    {"InstanceId": "i-ready", "AvailabilityZone": "a", "LifecycleState": "InService"},
                    {"InstanceId": "i-initial", "AvailabilityZone": "b", "LifecycleState": "InService"},
                    {"InstanceId": "i-pending", "AvailabilityZone": "a", "LifecycleState": "Pending"},
                ],
            }]}

        def describe_target_health(self, **kwargs):
            return {"TargetHealthDescriptions": [
                {"Target": {"Id": "i-ready"}, "TargetHealth": {"State": "healthy"}},
                {"Target": {"Id": "i-initial"}, "TargetHealth": {"State": "initial"}},
            ]}

    monkeypatch.setattr(scaling, "client", lambda service: Aws())
    response = client.get("/api/scaling")
    assert response.status_code == 200
    body = response.json()
    assert body["ready"] == 1
    assert body["deploying"] == 3  # incluye la EC2 todavía sin ID
    assert body["instances"][1]["state"] == "deploying"


def test_scaling_failure_does_not_break_health(client, monkeypatch):
    def fail():
        raise RuntimeError("AWS no disponible")

    monkeypatch.setattr(scaling, "summary", fail)
    response = client.get("/api/scaling")
    assert response.status_code == 503
    assert response.json()["status"] == "unavailable"
    assert client.get("/health").json() == {"status": "ok"}


def test_scaling_local_is_disabled(client, monkeypatch):
    monkeypatch.delenv("AUTOSCALING_GROUP_NAME", raising=False)
    assert client.get("/api/scaling").json() == {"status": "disabled", "instances": []}
