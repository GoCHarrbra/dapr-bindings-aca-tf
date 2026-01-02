variable "location" {
  type    = string
}

variable "rg_name" {
  type    = string
}

variable "env_name" {
  type    = string
}

variable "publisher_app_name" {
  type    = string
}

variable "worker_app_name" {
  type    = string
}

variable "publisher_image" {
  type    = string
}

variable "worker_image" {
  type    = string
}

variable "publisher_port" {
  type    = number
}

variable "worker_port" {
  type    = number
}

variable "sb_namespace_name" {
  type    = string
}

variable "sb_queue_name" {
  type    = string
}

variable "worker_min_replicas" {
  type    = number
}

variable "worker_max_replicas" {
  type    = number
}

variable "keda_message_threshold" {
  type    = number
}
