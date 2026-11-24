import argparse
import time
from config import consumer, settings

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", default=settings()["topic"])
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()
    client = consumer(args.topic)
    try:
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            for records in client.poll(timeout_ms=1000).values():
                for record in records:
                    print(f"CONSUMER_OK partition={record.partition} offset={record.offset} value={record.value}")
                    return
        raise SystemExit("No message received before timeout.")
    finally:
        client.close()

if __name__ == "__main__":
    main()
