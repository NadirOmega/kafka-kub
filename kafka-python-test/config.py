import json
from pathlib import Path
from kafka import KafkaProducer, KafkaConsumer

ROOT = Path(__file__).resolve().parent

def settings():
    path = ROOT / "config.local.json"
    if not path.is_file():
        raise SystemExit("Copy config.example.json to config.local.json and set the Route hostname.")
    data = json.loads(path.read_text(encoding="utf-8"))
    endpoint = data["bootstrap_servers"]
    if "REPLACE_" in endpoint or not endpoint.endswith(":443") or "://" in endpoint:
        raise SystemExit("Set bootstrap_servers to the actual Route hostname:443 (without https://).")
    return data

def kafka_config():
    opts = {"bootstrap_servers": settings()["bootstrap_servers"],
            "security_protocol": "SSL", "ssl_check_hostname": True,
            "request_timeout_ms": 10000, "api_version_auto_timeout_ms": 10000}
    for param, name in [("ssl_cafile", "ca.crt"), ("ssl_certfile", "client.crt"),
                        ("ssl_keyfile", "client.key")]:
        path = ROOT / "certificates" / name
        if not path.is_file():
            raise SystemExit(f"Missing certificate: {path}")
        opts[param] = str(path)
    return opts

def producer():
    return KafkaProducer(**kafka_config(), acks="all", max_block_ms=15000,
                         value_serializer=lambda value: value.encode("utf-8"))

def consumer(topic, group_id=None):
    return KafkaConsumer(topic, **kafka_config(), group_id=group_id,
                         enable_auto_commit=False, auto_offset_reset="earliest",
                         value_deserializer=lambda value: value.decode("utf-8"))
