# -------------------------
# Resource Group + Logs (recommended)
# -------------------------
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.rg_name}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# -------------------------
# Container Apps Environment
# -------------------------
resource "azurerm_container_app_environment" "env" {
  name                       = var.env_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# -------------------------
# Service Bus Namespace + Queue
# (azurerm v4 uses namespace_id on the queue resource)
# -------------------------
resource "azurerm_servicebus_namespace" "sb" {
  name                = var.sb_namespace_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}

resource "azurerm_servicebus_queue" "orders" {
  name         = var.sb_queue_name
  namespace_id = azurerm_servicebus_namespace.sb.id

  lock_duration                        = "PT1M"
  max_delivery_count                   = 10
  dead_lettering_on_message_expiration = true
}

data "azurerm_servicebus_namespace_authorization_rule" "root" {
  name                = "RootManageSharedAccessKey"
  namespace_name      = azurerm_servicebus_namespace.sb.name
  resource_group_name = azurerm_resource_group.rg.name
}

# -------------------------
# Dapr Components (ENV scope)
# - orders-output: Publisher -> Service Bus queue (output binding)
# - orders-input : Service Bus queue -> Worker route (input binding)
#
# Uses Dapr component secrets and metadata.secret_name
# -------------------------

resource "azurerm_container_app_environment_dapr_component" "orders_output" {
  name                         = "orders-output"
  container_app_environment_id = azurerm_container_app_environment.env.id
  component_type               = "bindings.azure.servicebusqueues"
  version                      = "v1"

  secret {
    name  = "sb-conn"
    value = data.azurerm_servicebus_namespace_authorization_rule.root.primary_connection_string
  }

  metadata {
    name        = "connectionString"
    secret_name = "sb-conn"
  }

  metadata {
    name  = "queueName"
    value = var.sb_queue_name
  }

  scopes = [var.publisher_app_name]
}

resource "azurerm_container_app_environment_dapr_component" "orders_input" {
  name                         = "orders-input"
  container_app_environment_id = azurerm_container_app_environment.env.id
  component_type               = "bindings.azure.servicebusqueues"
  version                      = "v1"

  secret {
    name  = "sb-conn"
    value = data.azurerm_servicebus_namespace_authorization_rule.root.primary_connection_string
  }

  metadata {
    name        = "connectionString"
    secret_name = "sb-conn"
  }

  metadata {
    name  = "queueName"
    value = var.sb_queue_name
  }

  # Dapr will POST to http://localhost:<worker_port>/sb-queue-in
  metadata {
    name  = "route"
    value = "sb-queue-in"
  }

  scopes = [var.worker_app_name]
}

# -------------------------
# Publisher Container App (External ingress)
# Dapr enabled: app_id + app_port + protocol
# -------------------------
resource "azurerm_container_app" "publisher" {
  name                         = var.publisher_app_name
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"

  ingress {
    external_enabled = true
    target_port      = var.publisher_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  dapr {
    app_id       = var.publisher_app_name
    app_port     = var.publisher_port
    app_protocol = "http"
  }

  template {
    container {
      name   = "publisher"
      image  = var.publisher_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "PORT"
        value = tostring(var.publisher_port)
      }

      # Optional: make binding name configurable in app
      env {
        name  = "SB_OUT_BINDING"
        value = "orders-output"
      }
    }

    min_replicas = 1
    max_replicas = 3
  }

  depends_on = [
    azurerm_container_app_environment_dapr_component.orders_output
  ]
}

# -------------------------
# Worker Container App (No ingress)
# Dapr enabled so Dapr can deliver input binding events locally.
# KEDA scaling: servicebus queue length
# -------------------------
resource "azurerm_container_app" "worker" {
  name                         = var.worker_app_name
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"

  dapr {
    app_id       = var.worker_app_name
    app_port     = var.worker_port
    app_protocol = "http"
  }

  # KEDA auth secret for the scale rule
  secret {
    name  = "sb-connection"
    value = data.azurerm_servicebus_namespace_authorization_rule.root.primary_connection_string
  }

  template {
    container {
      name   = "worker"
      image  = var.worker_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "PORT"
        value = tostring(var.worker_port)
      }

      env {
        name  = "BINDING_ROUTE"
        value = "sb-queue-in"
      }
    }

    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas

  custom_scale_rule {
    name            = "servicebus-scale"
    custom_rule_type = "azure-servicebus"
  
    metadata = {
      queueName    = var.sb_queue_name
      namespace    = azurerm_servicebus_namespace.sb.name
      messageCount = tostring(var.keda_message_threshold)
    }
  
    authentication {
      secret_name       = "sb-connection"
      trigger_parameter = "connection"
    }
  }
  }

  depends_on = [
    azurerm_container_app_environment_dapr_component.orders_input
  ]
}
