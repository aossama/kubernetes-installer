locals {
  failure_domains = length(var.failure_domains) == 0 ? [{
    datacenter = var.vsphere_datacenter
    cluster = var.vsphere_cluster
    datastore = var.vsphere_datastore
    network = var.vm_network
    distributed_virtual_switch_uuid = ""
  }] : var.failure_domains

  common_config_patches = [
    templatefile("${path.module}/templates/machine-install.yaml.tmpl", {}),
    templatefile("${path.module}/templates/machine-kubelet.yaml.tmpl", {
      machine_cidrs = var.machine_cidrs
    }),
    templatefile("${path.module}/templates/machine-sans.yaml.tmpl", {
      cluster_domain = local.cluster_domain
    }),
    templatefile("${path.module}/templates/machine-nameservers.yaml.tmpl", {
      nameservers = var.nameservers
    }),
    templatefile("${path.module}/templates/machine-timeservers.yaml.tmpl", {
      ntpservers = var.ntpservers
    }),
    templatefile("${path.module}/templates/registry-mirrors.yaml.tmpl", {
      registries_mirrors = var.registries_mirrors
    }),
    templatefile("${path.module}/templates/machine-files.yaml.tmpl", {
      additional_ca = var.additional_ca
    }),
    templatefile("${path.module}/templates/cluster-network.yaml.tmpl", {
      cluster_network = var.cluster_network
    }),
    templatefile("${path.module}/templates/cluster-kube-proxy.yaml.tmpl", {
      cluster_kube_proxy = var.cluster_kube_proxy
    }),
    file("${path.module}/files/cluster-discovery.yaml"),
  ]

  failure_domain_count  = length(local.failure_domains)
  cluster_domain        = format("%s.%s", var.cluster_name, var.base_domain)
  cluster_endpoint      = format("%s.%s", "api", local.cluster_domain)
  control_plane_fqdns   = [for idx in range(length(var.control_plane_ip_addresses)) : "control-plane-${idx}.${local.cluster_domain}"]
  compute_fqdns         = [for idx in range(length(var.compute_ip_addresses)) : "compute-${idx}.${local.cluster_domain}"]
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
  tags                    = [vsphere_tag.tag[count.index % local.failure_domain_count].id]
}

resource "vsphere_folder" "folder" {
  count = length(local.datacenters_distinct)
  path          = var.cluster_name
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc[index(data.vsphere_datacenter.dc.*.name, local.datacenters_distinct[count.index])].id
  tags          = [vsphere_tag.tag[count.index % local.failure_domain_count].id]
}

resource "vsphere_tag_category" "category" {
  count = length(local.datacenters_distinct)

  name        = format("k8s-%s", var.cluster_name)
  description = "Added by kubernetes installer, do not remove!"
  cardinality = "SINGLE"

  associable_types = [
    "VirtualMachine",
    "ResourcePool",
    "Folder",
    "Datastore",
    "StoragePod"
  ]
}

resource "vsphere_tag" "tag" {
  count = length(local.datacenters_distinct)

  name        = var.cluster_name
  category_id = vsphere_tag_category.category[count.index].id
  description = "Added by kubernetes installer, do not remove!"
}

resource "vsphere_content_library" "talos_content_library" {
  count = length(local.datacenters_distinct)
  name            = "Talos Content Library"
  description     = "Content library for hosting Talos templates"
  storage_backing = [data.vsphere_datastore.datastore[count.index % local.failure_domain_count].id]
}

resource "vsphere_content_library_item" "talos_template" {
  count       = length(local.datacenters_distinct)
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
  count = length(var.control_plane_ip_addresses) == 0 ? var.control_plane_count : length(var.control_plane_ip_addresses)
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
  tags                  = [vsphere_tag.tag[count.index % local.failure_domain_count].id]
  cluster_domain        = local.cluster_domain
  gateway               = var.gateway
  num_cpus              = var.control_plane_num_cpus
  memory                = var.control_plane_memory
  nameservers           = var.nameservers
  ntpservers            = var.ntpservers
  registries_mirrors    = var.registries_mirrors
  additional_ca         = var.additional_ca

  vm_machine_secret     = talos_machine_secrets.this.machine_secrets
  machine_type          = data.talos_machine_configuration.controlplane.machine_type
  cluster_name          = data.talos_machine_configuration.controlplane.cluster_name
  cluster_endpoint      = data.talos_machine_configuration.controlplane.cluster_endpoint

  config_patches        = concat(local.common_config_patches, data.talos_machine_configuration.controlplane.config_patches)
}

data "talos_client_configuration" "this" {
  cluster_name    = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes = [for k, v in var.control_plane_ip_addresses : v]
  endpoints = [local.cluster_endpoint]
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [
    module.control_plane_vm
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for k, v in var.control_plane_ip_addresses : v][0]
  endpoint = local.cluster_endpoint
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = "https://${local.cluster_endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches   = []
}

module "worker_vm" {
  depends_on = [
    talos_machine_bootstrap.bootstrap
  ]

  count = length(var.compute_ip_addresses) == 0 ? var.compute_count : length(var.compute_ip_addresses)
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
  tags                  = [vsphere_tag.tag[count.index % local.failure_domain_count].id]
  cluster_domain        = local.cluster_domain
  gateway               = var.gateway
  num_cpus              = var.compute_num_cpus
  memory                = var.compute_memory
  nameservers           = var.nameservers
  ntpservers            = var.ntpservers
  registries_mirrors    = var.registries_mirrors
  additional_ca         = var.additional_ca

  vm_machine_secret     = talos_machine_secrets.this.machine_secrets
  machine_type          = data.talos_machine_configuration.worker.machine_type
  cluster_name          = data.talos_machine_configuration.worker.cluster_name
  cluster_endpoint      = data.talos_machine_configuration.worker.cluster_endpoint

  config_patches        = concat(local.common_config_patches, data.talos_machine_configuration.worker.config_patches)
}

data "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on = [
    talos_machine_bootstrap.bootstrap
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node = [for k, v in var.control_plane_ip_addresses : v][0]
}
