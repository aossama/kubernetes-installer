locals {
  failure_domains = length(var.failure_domains) == 0 ? [{
    datacenter = var.vsphere_datacenter
    cluster = var.vsphere_cluster
    datastore = var.vsphere_datastore
    network = var.vm_network
    distributed_virtual_switch_uuid = ""
  }] : var.failure_domains

  failure_domain_count  = length(local.failure_domains)
  cluster_domain        = format("%s.%s", var.cluster_name, var.base_domain)
  cluster_endpoint      = format("%s.%s", "api", var.cluster_domain)
  control_plane_fqdns   = [for idx in range(length(var.control_plane_ip_addresses)) : "control-plane-${idx}.${var.cluster_domain}"]
  compute_fqdns         = [for idx in range(length(var.compute_ip_addresses)) : "compute-${idx}.${var.cluster_domain}"]
  datastores            = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datastore"]]
  datacenters           = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datacenter"]]
  datacenters_distinct  = distinct([for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["datacenter"]])
  clusters              = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["cluster"]]
  networks              = [for idx in range(length(local.failure_domains)) : local.failure_domains[idx]["cluster"]]
  folders               = [for idx in range(length(local.datacenters)) : "/${local.datacenters[idx]}/vm/${var.cluster_name}"]
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
  name                    = var.cluster_name
  parent_resource_pool_id = data.vsphere_compute_cluster.compute_cluster[count.index].resource_pool_id
}

resource "vsphere_folder" "folder" {
  count = length(local.datacenters_distinct)
  path          = var.cluster_name
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

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches   = [
    file("${path.module}/files/cp-scheduling.yaml"),
  ]
}

module "control_plane_vm" {
  count = length(var.control_plane_ip_addresses)
  source = "./vm"

  vmname                = format("%s-cp-%02s", var.cluster_name, count.index + 1)
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

  vm_machine_secret     = talos_machine_secrets.this.machine_secrets
  machine_type          = data.talos_machine_configuration.controlplane.machine_type
  cluster_name          = data.talos_machine_configuration.controlplane.cluster_name
  cluster_endpoint      = data.talos_machine_configuration.controlplane.cluster_endpoint
}

data "talos_machine_configuration" "worker" {
  depends_on = [
    module.control_plane_vm
  ]

  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches   = [
    file("${path.module}/files/cp-scheduling.yaml"),
  ]
}

module "worker_vm" {
  depends_on = [
    data.talos_machine_configuration.worker
  ]

  count = length(var.compute_ip_addresses)
  source = "./vm"

  vmname                = format("%s-worker-%02s", var.cluster_name, count.index + 1)
  ipaddress             = var.compute_ip_addresses[count.index]
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
  num_cpus              = var.compute_num_cpus
  memory                = var.compute_memory
  dns_addresses         = var.vm_dns_addresses

  vm_machine_secret     = talos_machine_secrets.this.machine_secrets
  machine_type          = data.talos_machine_configuration.worker.machine_type
  cluster_name          = data.talos_machine_configuration.worker.cluster_name
  cluster_endpoint      = data.talos_machine_configuration.worker.cluster_endpoint
}
