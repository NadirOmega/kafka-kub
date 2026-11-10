package example.kafka;

import java.time.Duration;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.StringSerializer;

public final class ProducerApp {
    public static void main(String[] args) throws Exception {
        String bootstrap = env("KAFKA_BOOTSTRAP_SERVERS", "kafka-poc-bootstrap:9092");
        String topic = env("KAFKA_TOPIC", "test-kafka");
        int count = Integer.parseInt(env("MESSAGE_COUNT", "10"));
        if (count < 1 || count > 10000) {
            throw new IllegalArgumentException("MESSAGE_COUNT must be between 1 and 10000");
        }

        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");
        props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, "30000");
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, "10000");

        String runId = UUID.randomUUID().toString().substring(0, 8);
        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            for (int i = 1; i <= count; i++) {
                String key = runId + "-" + i;
                String value = "java-producer run=" + runId + " message=" + i;
                RecordMetadata metadata = producer.send(new ProducerRecord<>(topic, key, value))
                    .get(30, TimeUnit.SECONDS);
                System.out.printf("SENT topic=%s partition=%d offset=%d key=%s value=%s%n",
                    metadata.topic(), metadata.partition(), metadata.offset(), key, value);
            }
            producer.flush();
        }
        System.out.println("PRODUCER_OK sent=" + count);
    }

    private static String env(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }
}
