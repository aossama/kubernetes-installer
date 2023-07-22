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

variable "machine_cidr" {
  type = string
}

variable "memory" {
  type = string
}

variable "num_cpus" {
  type = string
}

variable "dns_addresses" {
  type = list(string)
}

variable "vmname" {
  type = string
}

variable "ipaddress" {
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

variable "vm_machine_secret" {}