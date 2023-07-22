locals {
  failure_domains = length(var.failure_domains) == 0 ? [{
    datacenter = var.vsphere_datacenter
    cluster = var.vsphere_cluster
    datastore = var.vsphere_datastore
    network = var.vm_network
    distributed_virtual_switch_uuid = ""
  }] : var.failure_domains

  failure_domain_count  = length(local.failure_domains)
  cluster_domain        = formatlist("%s.%s", var.cluster_id, var.base_domain)
  api_lb_fqdns          = formatlist("%s.%s", "api", var.cluster_domain)
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

## Remote OVF/OVA Source
data "vsphere_ovf_vm_template" "ovfRemote" {
  count = length(local.datacenters_distinct)
  name              = "${var.cluster_id}-talos-template"
  folder            = vsphere_folder.folder[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].path
  disk_provisioning = "thin"
  resource_pool_id  = vsphere_resource_pool.resource_pool[count.index % local.failure_domain_count].id
  datastore_id      = data.vsphere_datastore.datastore[count.index % local.failure_domain_count].id
  host_system_id    = data.vsphere_host.host.id
  remote_ovf_url    = "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/vmware-amd64.ova"
  ovf_network_map = {
    "VM Network" : data.vsphere_network.network[count.index % local.failure_domain_count].id
  }
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
  ovfRemote             = data.vsphere_ovf_vm_template.ovfRemote[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])]
  guest_id              = data.vsphere_ovf_vm_template.ovfRemote[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].guest_id
  template_uuid         = data.vsphere_ovf_vm_template.ovfRemote[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count ]["datacenter"])].id
  disk_thin_provisioned = data.vsphere_ovf_vm_template.ovfRemote[index(data.vsphere_datacenter.dc.*.name, local.failure_domains[count.index % local.failure_domain_count]["datacenter"])].disks[0].thin_provisioned
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