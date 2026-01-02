output "publisher_fqdn" {
  description = "Publisher FQDN (append /orders)"
  value       = azurerm_container_app.publisher.latest_revision_fqdn
}

output "publisher_orders_url" {
  description = "Full URL you can curl to send messages"
  value       = "https://${azurerm_container_app.publisher.latest_revision_fqdn}/orders"
}

output "servicebus_namespace" {
  description = "Service Bus namespace"
  value       = azurerm_servicebus_namespace.sb.name
}

output "servicebus_queue" {
  description = "Service Bus queue name"
  value       = azurerm_servicebus_queue.orders.name
}
