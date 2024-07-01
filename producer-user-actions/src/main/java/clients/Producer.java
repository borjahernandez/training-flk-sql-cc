package clients;

import io.confluent.kafka.serializers.KafkaAvroSerializer;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Properties;
import java.time.Instant;

import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;

public class Producer {
  static final String DATA = (System.getenv("DATA") != null) ? System.getenv("DATA") : "user_actions_1.csv";
  static final String PROPERTIES_FILE = (System.getenv("PROPERTIES_FILE") != null) ? System.getenv("PROPERTIES_FILE") : "./java-producer.properties";
  static final String KAFKA_TOPIC = (System.getenv("TOPIC") != null) ? System.getenv("TOPIC") : "user_actions";

  /**
   * Java producer.
   */
  public static void main(String[] args) throws IOException, InterruptedException {
    clients.avro.key.record ActionsKey = new clients.avro.key.record();
    clients.avro.value.record ActionsValue = new clients.avro.value.record();
    System.out.println("Starting Java Avro producer.");

    // Configure the location of the bootstrap server, default serializers,
    // Confluent interceptors, schema registry location
    final Properties settings = loadPropertiesFile();
    settings.put(ProducerConfig.CLIENT_ID_CONFIG, "producer-user-actions");
    settings.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class);
    settings.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class);
    
    final KafkaProducer<clients.avro.key.record, clients.avro.value.record> producer = new KafkaProducer<>(settings);
    
    // Adding a shutdown hook to clean up when the application exits
    Runtime.getRuntime().addShutdownHook(new Thread(() -> {
      System.out.println("Closing producer.");
      producer.close();
    }));

    int pos = 0;
    final String[] rows = Files.readAllLines(Paths.get("./user-actions/" + DATA),
      Charset.forName("UTF-8")).toArray(new String[0]);

    // Loop forever over the driver CSV file..
    for (int i = 0; i < rows.length; i++) {
      final String user = rows[i].split(",")[0];
      final String action = rows[i].split(",")[1];
      final Instant timestamp = Instant.ofEpochMilli(Long.parseLong(rows[i].split(",")[2]));
      final clients.avro.key.record key = new clients.avro.key.record(user);
      final clients.avro.value.record value = new clients.avro.value.record(action, timestamp);
      final ProducerRecord<clients.avro.key.record, clients.avro.value.record> record = new ProducerRecord<>(
          KAFKA_TOPIC, key, value);
      producer.send(record, (md, e) -> {
        System.out.println();
        System.out.println(String.format("Sent Key:%s Value:%s",
            key, value));
      });
      Thread.sleep(2000);
    }

    /*
    Confirm the topic is being written to with kafka-avro-console-consumer
    
    kafka-avro-console-consumer --bootstrap-server kafka:9092 \
    --property schema.registry.url=http://schema-registry:8081 \
    --topic driver-positions-avro --property print.key=true \
    --key-deserializer=org.apache.kafka.common.serialization.StringDeserializer \
    --from-beginning

    curl schema-registry:8081/subjects/driver-positions-avro-value/versions/1
    */

  }


  public static Properties loadPropertiesFile() throws IOException {
    if (!Files.exists(Paths.get(PROPERTIES_FILE))) {
      throw new IOException(PROPERTIES_FILE + " not found.");
    }
    final Properties properties = new Properties();
    try (InputStream inputStream = new FileInputStream(PROPERTIES_FILE)) {
      properties.load(inputStream);
    }
    return properties;
  }
}