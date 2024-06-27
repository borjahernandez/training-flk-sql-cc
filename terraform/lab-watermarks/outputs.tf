output "resource-ids" {
  value = <<-EOT
  bootstrap.servers=${confluent_kafka_cluster.basic.bootstrap_endpoint}
  security.protocol=SASL_SSL
  sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule   required username='${confluent_api_key.app-manager-watermarks-kafka-api-key.id}'   password='${confluent_api_key.app-manager-watermarks-kafka-api-key.secret}';
  sasl.mechanism=PLAIN

  schema.registry.url=${confluent_schema_registry_cluster.essentials.rest_endpoint}
  basic.auth.credentials.source=USER_INFO
  basic.auth.user.info=${confluent_api_key.app-manager-watermarks-schema-registry-api-key.id}:${confluent_api_key.app-manager-watermarks-schema-registry-api-key.secret}
  EOT

  sensitive = true
}