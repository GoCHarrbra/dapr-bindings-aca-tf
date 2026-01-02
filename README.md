# dapr-bindings-aca-tf
This repo provisions Azure Container Apps with Dapr enabled and an Azure Service Bus Queue, wired together via a Dapr binding (bindings.azure.servicebusqueues) using a Service Bus SAS connection string by default (stored as a Dapr component secret). The Dapr component is scoped to the target app’s Dapr app ID
