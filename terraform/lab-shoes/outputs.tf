output "resource-ids" {
  value = <<-EOT
  Environment ID:   ${confluent_environment.shoe-env.id}
  Kafka Cluster ID: ${confluent_kafka_cluster.basic.id}

  Service Accounts and their Kafka API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.app-shoe-manager.display_name}:                     ${confluent_service_account.app-shoe-manager.id}
  ${confluent_service_account.app-shoe-manager.display_name}'s Kafka API Key:     "${confluent_api_key.app-shoe-manager-kafka-api-key.id}"
  ${confluent_service_account.app-shoe-manager.display_name}'s Kafka API Secret:  "${confluent_api_key.app-shoe-manager-kafka-api-key.secret}"
  EOT

  sensitive = true
}