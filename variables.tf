//////
// vSphere variables
//////

variable "vsphere_server" {
  type        = string
  description = "This is the vSphere vCenter server for the environment"
}

variable "vsphere_user" {
  type        = string
  description = "vSphere server username for the environment"
}

variable "vsphere_password" {
  type        = string
  description = "vSphere server password"
}

variable "vsphere_cluster" {
  type        = string
  default     = ""
  description = "This is the name of the vSphere cluster."
}

variable "vsphere_datacenter" {
  type        = string
  default     = ""
  description = "This is the name of the vSphere data center."
}

variable "vsphere_datastore" {
  type        = string
  default     = ""
  description = "This is the name of the vSphere data store."
}

variable "vm_network" {
  type        = string
  description = "This is the name of the publicly accessible network for cluster ingress and access."
  default     = "VM Network"
}

variable "gateway" {
  type        = string
  description = "Network gateway"
  default     = ""
}

variable "nameservers" {
  type    = list(string)
  default = ["8.8.8.8", "1.1.1.1"]
}

variable "ntpservers" {
  type    = list(string)
  default = ["0.pool.ntp.org", "time.google.com"]
}

/////////
// Kubernetes cluster variables
/////////

variable "kubernetes_version" {
  type = string
  description = "Desired kubernetes version to run"
}

variable "talos_version" {
  type = string
  description = "Desired Talos version to generate config for"
}

variable "ova_url" {
  type = string
  description = "URL Prefix for the OVA file"
  default = "https://github.com/siderolabs/talos/releases/download"
}

variable "cluster_name" {
  type        = string
  description = "This cluster id must be of max length 27 and must have only alphanumeric or hyphen characters"
}

variable "base_domain" {
  type        = string
  description = "The base DNS zone to add the sub zone to"
}

variable "machine_cidrs" {
  type = list(string)
  default = []
}

variable "registries_mirrors" {
  description = "A map of local mirrored registries"
  type = map(object({
    endpoints = list(string)
  }))
  default = {}
}

variable "additional_ca" {
  description = "Additional CAs to be installed on nodes"
  type = list(string)
  default = []
}

variable "cluster_kube_proxy" {
  description = "Kube-proxy server-specific configuration options"
  type = bool
  default = true
}

variable "cluster_network" {
  description = "Provides cluster specific network configuration options"
  type = object({
    name = string
    dnsDomain = string
    pod_subnets = list(string)
    service_subnets = list(string)
  })

  default = {
    name = "flannel"
    dnsDomain = "cluster.local"
    pod_subnets = ["10.244.0.0/14"]
    service_subnets = ["10.96.0.0/16"]
  }

  validation {
    condition     = length(regexall("^(flannel|none)$", var.cluster_network["name"])) > 0
    error_message = "ERROR: Valid types are \"flannel\" and \"none\"!"
  }
}

///////////
// control-plane machine variables
///////////

variable "control_plane_count" {
  type    = number
  default = 3
  description = "The number of control plane machines to provision"

  validation {
    condition     = var.control_plane_count == 1 || var.control_plane_count == 3
    error_message = "ERROR: Only 1 or 3 control plane node count is allowed! Please specify either 1 or 3 control plane nodes."
  }
}

variable "control_plane_ip_addresses" {
  type    = list(string)
  default = []
  description = "The IP addresses to assign to the control plane VMs"

  validation {
    condition = length(var.control_plane_ip_addresses) == 0 || (length(var.control_plane_ip_addresses) == 1 || length(var.control_plane_ip_addresses) == 3)
    error_message = "ERROR: Only 1 and 3 control plane node IPs are allowed! Please specify either 1 IP or 3 distinct IPs."
  }

  validation {
    condition     = length(var.control_plane_ip_addresses) == 0 || length(var.control_plane_ip_addresses) == length(distinct(var.control_plane_ip_addresses))
    error_message = "ERROR: Control plane node IPs must be distinct."
  }
}

variable "control_plane_memory" {
  type    = string
  default = "16384"
  description = "The size of a virtual machine’s memory in megabytes"
}

variable "control_plane_num_cpus" {
  type    = string
  default = "4"
  description = "The total number of virtual processor cores to assign a virtual machine"
}

//////////
// compute machine variables
//////////

variable "compute_count" {
  type    = number
  default = 2
  description = "The IP addresses to assign to the compute VMs"

  validation {
    condition     = var.compute_count >= 2
    error_message = "ERROR: compute node count must be at least 2 nodes."
  }
}

variable "compute_ip_addresses" {
  type    = list(string)
  default = []

  validation {
    condition = length(var.compute_ip_addresses) == 0 || length(var.compute_ip_addresses) >= 2
    error_message = "ERROR: Please specify at least 2 IPs for the compute nodes."
  }

  validation {
    condition     = length(var.compute_ip_addresses) == 0 || length(var.compute_ip_addresses) == length(distinct(var.compute_ip_addresses))
    error_message = "ERROR: compute node IPs must be distinct."
  }
}

variable "compute_memory" {
  type    = string
  default = "8192"
  description = "The size of a virtual machine’s memory in megabytes"
}

variable "compute_num_cpus" {
  type    = string
  default = "4"
  description = "The total number of virtual processor cores to assign a virtual machine"
}

///////////////////////////////////////////
///// failure domains
///// if not defined, a default failure domain is created which consists of:
///// vsphere_cluster, vsphere_datacenter, vsphere_datastore, vmware_network
/////
///// each element in the list must consist of:
/////{
/////        datacenter = "the-datacenter"
/////        cluster = "the-cluster"
/////        datastore = "the-datastore"
/////        network = "the-portgroup"
/////        distributed_virtual_switch_uuid = "uuid-of-the-dvs-where-the-portgroup-attached"
/////}
///////////////////////////////////////////
variable "failure_domains" {
  type = list(map(string))
  description = "Defines a list of failure domains"
  default = []
}