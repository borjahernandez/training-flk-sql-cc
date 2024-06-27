terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "1.77.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

data "confluent_organization" "main" {}

resource "confluent_environment" "watermarks-env" {
  display_name = "watermarks-env"
}

# Stream Governance and Kafka clusters can be in different regions as well as different cloud providers,
# but you should to place both in the same cloud and region to restrict the fault isolation boundary.
data "confluent_schema_registry_region" "essentials" {
  cloud   = "AWS"
  region  = "us-east-2"
  package = "ESSENTIALS"
}

resource "confluent_schema_registry_cluster" "essentials" {
  package = data.confluent_schema_registry_region.essentials.package

  environment {
    id = confluent_environment.watermarks-env.id
  }

  region {
    # See https://docs.confluent.io/cloud/current/stream-governance/packages.html#stream-governance-regions
    id = data.confluent_schema_registry_region.essentials.id
  }
}

# Update the config to use a cloud provider and region of your choice.
# https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_cluster
resource "confluent_kafka_cluster" "basic" {
  display_name = "watermarks-cluster"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = "us-east-2"
  basic {}
  environment {
    id = confluent_environment.watermarks-env.id
  }
}

// 'app-manager-watermarks' service account is required in this configuration to create 'clicks' topic
resource "confluent_service_account" "app-manager-watermarks" {
  display_name = "app-manager-watermarks"
  description  = "Service account to manage 'watermarks-cluster' Kafka cluster"
}

resource "confluent_role_binding" "app-manager-watermarks-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager-watermarks.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

resource "confluent_api_key" "app-manager-watermarks-kafka-api-key" {
  display_name = "app-manager-watermarks-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager-watermarks' service account"
  owner {
    id          = confluent_service_account.app-manager-watermarks.id
    api_version = confluent_service_account.app-manager-watermarks.api_version
    kind        = confluent_service_account.app-manager-watermarks.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.watermarks-env.id
    }
  }


  resource "confluent_api_key" "app-manager-watermarks-schema-registry-api-key" {
  display_name = "app-manager-watermarks-schema-registry-api-key"
  description  = "Schema Registry API Key that is owned by 'app-manager-watermarks' service account"
  owner {
    id          = confluent_service_account.app-manager-watermarks.id
    api_version = confluent_service_account.app-manager-watermarks.api_version
    kind        = confluent_service_account.app-manager-watermarks.kind
  }

  managed_resource {
    id          = confluent_schema_registry_cluster.essentials.id
    api_version = onfluent_schema_registry_cluster.essentials.api_version
    kind        = onfluent_schema_registry_cluster.essentials.kind

    environment {
      id = confluent_environment.watermarks-env.id
    }

    lifecycle {
      prevent_destroy = true
    }
  }

  # The goal is to ensure that confluent_role_binding.app-manager-watermarks-kafka-cluster-admin is created before
  # confluent_api_key.app-manager-watermarks-kafka-api-key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.app-manager-watermarks-kafka-api-key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.app-manager-watermarks-kafka-cluster-admin
  ]
}


// Service account to perform a task within Confluent Cloud, such as executing a Flink statement
resource "confluent_service_account" "statements-runner" {
  display_name = "statements-runner"
  description  = "Service account for running Flink Statements in 'watermarks-cluster' Kafka cluster"
}

resource "confluent_role_binding" "statements-runner-environment-admin" {
  principal   = "User:${confluent_service_account.statements-runner.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.watermarks-env.resource_name
}

// https://docs.confluent.io/cloud/current/access-management/access-control/rbac/predefined-rbac-roles.html#assigner
// https://docs.confluent.io/cloud/current/flink/operate-and-deploy/flink-rbac.html#submit-long-running-statements
resource "confluent_role_binding" "app-manager-watermarks-assigner" {
  principal   = "User:${confluent_service_account.app-manager-watermarks.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.statements-runner.id}"
}

// https://docs.confluent.io/cloud/current/access-management/access-control/rbac/predefined-rbac-roles.html#flinkadmin
resource "confluent_role_binding" "app-manager-watermarks-flink-developer" {
  principal   = "User:${confluent_service_account.app-manager-watermarks.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.watermarks-env.resource_name
}

resource "confluent_api_key" "app-manager-watermarks-flink-api-key" {
  display_name = "app-manager-watermarks-flink-api-key"
  description  = "Flink API Key that is owned by 'app-manager-watermarks' service account"
  owner {
    id          = confluent_service_account.app-manager-watermarks.id
    api_version = confluent_service_account.app-manager-watermarks.api_version
    kind        = confluent_service_account.app-manager-watermarks.kind
  }
  managed_resource {
    id          = data.confluent_flink_region.us-east-2.id
    api_version = data.confluent_flink_region.us-east-2.api_version
    kind        = data.confluent_flink_region.us-east-2.kind
    environment {
      id = confluent_environment.watermarks-env.id
    }
  }
}

data "confluent_flink_region" "us-east-2" {
  cloud   = "AWS"
  region  = "us-east-2"
}

# https://docs.confluent.io/cloud/current/flink/get-started/quick-start-cloud-console.html#step-1-create-a-af-compute-pool
resource "confluent_flink_compute_pool" "main" {
  display_name = "training-compute-pool"
  cloud   = "AWS"
  region  = "us-east-2"
  max_cfu      = 10
  environment {
    id = confluent_environment.watermarks-env.id
  }
  depends_on = [
    confluent_role_binding.statements-runner-environment-admin,
    confluent_role_binding.app-manager-watermarks-assigner,
    confluent_role_binding.app-manager-watermarks-flink-developer,
    confluent_api_key.app-manager-watermarks-flink-api-key,
  ]
}