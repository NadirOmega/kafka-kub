import argparse
from config import producer, settings

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", default=settings()["topic"])
    parser.add_argument("--message", default="Hello from Python")
    args = parser.parse_args()
    client = producer()
    try:
        result = client.send(args.topic, args.message).get(timeout=20)
        print(f"PRODUCER_OK topic={result.topic} partition={result.partition} offset={result.offset}")
    finally:
        client.close(timeout=5)

if __name__ == "__main__":
    main()
