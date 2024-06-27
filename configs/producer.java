package clients;

import clients.avro.ActionsKey;
import clients.avro.ActionsValue;

import io.confluent.kafka.serializers.KafkaAvroSerializer;
import io.confluent.kafka.serializers.KafkaAvroSerializerConfig;
import io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.List;
import java.util.Properties;
import java.time.Instant;

import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;

public class Producer {
  static final String DATA_FILE_PREFIX = "./user-actions/";
  static final String PROPERTIES_FILE = (System.getenv("PROPERTIES_FILE") != null) ? System.getenv("PROPERTIES_FILE") : "./java-producer.properties";
  static final String KAFKA_TOPIC = (System.getenv("TOPIC") != null) ? System.getenv("TOPIC") : "user_actions5";
  static final int NUM_RECORDS = Integer.parseInt((System.getenv("NUM_RECORDS") != null) ? System.getenv("NUM_RECORDS") : "1000000");


  /**
   * Java producer.
   */
  public static void main(String[] args) throws IOException, InterruptedException {
    System.out.println("Starting Java Avro producer.");

    // Configure the location of the bootstrap server, default serializers,
    // Confluent interceptors, schema registry location
    final Properties settings = loadPropertiesFile();
    settings.put(ProducerConfig.CLIENT_ID_CONFIG, "producer-user-actions");
    settings.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class);
    settings.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class);
    
    final KafkaProducer<ActionsKey, ActionsValue> producer = new KafkaProducer<>(settings);
    
    // Adding a shutdown hook to clean up when the application exits
    Runtime.getRuntime().addShutdownHook(new Thread(() -> {
      System.out.println("Closing producer.");
      producer.close();
    }));

    int pos = 0;
    final String[] rows = Files.readAllLines(Paths.get(DATA_FILE_PREFIX + "user_actions_1.csv"),
      Charset.forName("UTF-8")).toArray(new String[0]);

    // Loop forever over the driver CSV file..
    for (int i = 0; i < rows.length; i++) {
      final String user = rows[i].split(",")[0];
      final String action = rows[i].split(",")[1];
      final Instant timestamp = Instant.ofEpochMilli(Long.parseLong(rows[i].split(",")[2]));
      final ActionsKey key = new ActionsKey(user);
      final ActionsValue value = new ActionsValue(action, timestamp);
      final ProducerRecord<ActionsKey, ActionsValue> record = new ProducerRecord<>(
          KAFKA_TOPIC, key, value);
      producer.send(record, (md, e) -> {
        System.out.println(String.format("Sent Key:%s user:%s action:%s timestamp:%s",
            key, key.getUser(), value.getAction(), value.getTimestamp()));
      });
      Thread.sleep(1000);
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
