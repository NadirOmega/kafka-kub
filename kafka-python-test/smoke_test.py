import time
import uuid
from kafka.admin import KafkaAdminClient, NewTopic
from config import kafka_config, producer, consumer

def main():
    token = uuid.uuid4().hex
    topic = "external-python-smoke-" + token[:12]
    message = "EXTERNAL_NATIVE_TLS_OK:" + token
    admin = KafkaAdminClient(**kafka_config())
    try:
        admin.create_topics([NewTopic(topic, num_partitions=1, replication_factor=1)], timeout_ms=15000)
        print("TOPIC_CREATED:", topic)
    finally:
        admin.close()
    client = producer()
    try:
        metadata = client.send(topic, message).get(timeout=20)
        print("PRODUCER_OK offset=", metadata.offset)
    finally:
        client.close(timeout=5)
    reader = consumer(topic)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            for records in reader.poll(timeout_ms=1000).values():
                for record in records:
                    if record.value == message:
                        print("CONSUMER_OK")
                        print("NATIVE_KAFKA_443_OK")
                        return
        raise SystemExit("Smoke test failed: expected message not received.")
    finally:
        reader.close()
        print("Test topic retained:", topic)

if __name__ == "__main__":
    main()
