//////
// vSphere variables
//////
variable "disk_thin_provisioned" {
  type = bool
}

variable "template_uuid" {
  type = string
}

variable "guest_id" {
  type = string
}

variable "resource_pool_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "network_id" {
  type = string
}

variable "cluster_domain" {
  type = string
}

variable "datacenter_id" {
  type = string
}

variable "memory" {
  type = string
}

variable "num_cpus" {
  type = string
}

variable "nameservers" {
  type = list(string)
}

variable "ntpservers" {
  type = list(string)
}

variable "vmname" {
  type = string
}

variable "ipaddress" {
  type = string
}

variable "gateway" {
  type = string
}

/////////
// Talos variables
/////////
variable "cluster_name" {
  type = string
}

variable "machine_type" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "registries_mirrors" {
  type = map(object({
    endpoints = list(string)
  }))
}

variable "additional_ca" {
  type = list(string)
}

variable "vm_machine_secret" {}

variable "config_patches" {}