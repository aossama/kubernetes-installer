locals {
  failure_domains = length(var.failure_domains) == 0 ? [{
    datacenter = var.vsphere_datacenter
    cluster = var.vsphere_cluster
    datastore = var.vsphere_datastore
    network = var.vm_network
    distributed_virtual_switch_uuid = ""
  }] : var.failure_domains

  failure_domain_count  = length(local.failure_domains)
  cluster_domain        = format("%s.%s", var.cluster_id, var.base_domain)
  api_lb_fqdns          = format("%s.%s", "api", var.cluster_domain)
  control_plane_fqdns   = [for idx in range(var.control_plane_count) : "control-plane-${idx}.${var.cluster_domain}"]
  compute_fqdns         = [for idx in range(var.compute_count) : "compute-${idx}.${var.cluster_domain}"]
  datastores            = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datastore"]]
  datacenters           = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datacenter"]]
  datacenters_distinct  = distinct([for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datacenter"]])
  clusters              = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["cluster"]]
  networks              = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["cluster"]]
  folders               = [for idx in range(length(local.datacenters)) : "/${local.datacenters[idx]}/vm/${var.cluster_id}"]
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = false
}

data "vsphere_datacenter" "dc" {
  count = length(local.datacenters_distinct)
  name = local.datacenters_distinct[count.index]
}

data "vsphere_compute_cluster" "compute_cluster" {
  count = length(local.failure_domains)
  name = local.clusters[count.index]
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters[count.index])].id
}

data "vsphere_datastore" "datastore" {
  count = length(local.failure_domains)
  name = local.datastores[count.index]
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters[count.index])].id
}

data "vsphere_network" "network" {
  count = length(local.failure_domains)
  name          = local.failure_domains[count.index]["network"]
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index]["datacenter"])].id
  distributed_virtual_switch_uuid = local.failure_domains[count.index]["distributed_virtual_switch_uuid"]
}

resource "vsphere_resource_pool" "resource_pool" {
  count                   = length(data.vsphere_compute_cluster.compute_cluster)
  name                    = var.cluster_id
  parent_resource_pool_id = data.vsphere_compute_cluster.compute_cluster[count.index].resource_pool_id
}

resource "vsphere_folder" "folder" {
  count = length(local.datacenters_distinct)
  path          = var.cluster_id
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters_distinct[count.index])].id
}

resource "vsphere_content_library" "talos_content_library" {
  count = length(local.datacenters_distinct)
  name            = "Talos Content Library"
  description     = "Content library for hosting Talos templates"
  storage_backing = [data.vsphere_datastore.datastore[count.index % local.failure_domain_count].id]
}

resource "vsphere_content_library_item" "talos_template" {
  count = length(local.datacenters_distinct)
  name        = "talos-${var.talos_version}-template"
  description = "Talos version ${var.talos_version} template"
  file_url    = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/vmware-amd64.ova"
  library_id  = vsphere_content_library.talos_content_library[count.index % local.failure_domain_count].id
}

resource "talos_machine_secrets" "cp" {}

data "talos_machine_configuration" "cp" {
  cluster_name     = var.cluster_id
  machine_type     = "controlplane"
  cluster_endpoint = "https://${local.api_lb_fqdns}:6443"
  machine_secrets  = talos_machine_secrets.cp.machine_secrets
}

module "control_plane_vm" {
  count = var.control_plane_count
  source = "./vm"

  vmname                = "${var.cluster_id}-cp-${count.index}"
  ipaddress             = var.control_plane_ip_addresses[count.index]
  resource_pool_id      = vsphere_resource_pool.resource_pool[count.index % local.failure_domain_count].id
  datastore_id          = data.vsphere_datastore.datastore[count.index % local.failure_domain_count].id
  datacenter_id         = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].id
  network_id            = data.vsphere_network.network[count.index % local.failure_domain_count].id
  folder_id             = vsphere_folder.folder[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].path
  template_uuid         = vsphere_content_library_item.talos_template[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count ]["datacenter"])].id
  guest_id              = "otherLinux64Guest"
  disk_thin_provisioned = "true"
  cluster_domain        = var.cluster_domain
  machine_cidr          = var.machine_cidr
  num_cpus              = var.control_plane_num_cpus
  memory                = var.control_plane_memory
  dns_addresses         = var.vm_dns_addresses

  vm_machine_secret     = talos_machine_secrets.cp.machine_secrets
  machine_type          = data.talos_machine_configuration.cp.machine_type
  cluster_name          = data.talos_machine_configuration.cp.cluster_name
  cluster_endpoint      = data.talos_machine_configuration.cp.cluster_endpoint
}