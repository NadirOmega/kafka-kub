import socket
import ssl
from kafka.admin import KafkaAdminClient
from config import settings, kafka_config

def main():
    endpoint = settings()["bootstrap_servers"]
    host, port = endpoint.rsplit(":", 1)
    port = int(port)
    print("[1/4] DNS")
    socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    print("DNS OK")
    print("[2/4] TCP")
    with socket.create_connection((host, port), timeout=10):
        print("TCP OK")
    print("[3/4] TLS / mTLS")
    cfg = kafka_config()
    ctx = ssl.create_default_context(cafile=cfg["ssl_cafile"])
    ctx.load_cert_chain(cfg["ssl_certfile"], cfg["ssl_keyfile"])
    with socket.create_connection((host, port), timeout=10) as raw:
        with ctx.wrap_socket(raw, server_hostname=host) as tls:
            print("TLS handshake OK:", tls.version())
    print("[4/4] Kafka metadata")
    admin = KafkaAdminClient(**cfg)
    try:
        topics = admin.list_topics()
        print(f"KAFKA_METADATA_OK ({len(topics)} visible topics)")
    finally:
        admin.close()

if __name__ == "__main__":
    main()
