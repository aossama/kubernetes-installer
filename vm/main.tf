data "talos_machine_configuration" "this" {
  cluster_name     = var.cluster_name
  machine_type     = var.machine_type
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = var.vm_machine_secret
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = var.vmname
          interfaces = [
            {
              interface= "eth0"
              addresses = [
                var.ipaddress
              ]
            }
          ]
        }
      }
    })
  ]
}

resource "vsphere_virtual_machine" "vm" {
  name = var.vmname

  resource_pool_id = var.resource_pool_id
  datastore_id     = var.datastore_id
  num_cpus         = var.num_cpus
  memory           = var.memory
  guest_id         = var.guest_id
  folder           = var.folder_id
  enable_disk_uuid = "true"

  wait_for_guest_net_timeout  = 0
  wait_for_guest_ip_timeout   = 0
  wait_for_guest_net_routable = "false"

  network_interface {
    network_id = var.network_id
  }

  disk {
    label            = "disk0"
    size             = 150
    thin_provisioned = var.disk_thin_provisioned
  }

  ovf_deploy {
    allow_unverified_ssl_cert = false
    remote_ovf_url            = data.vsphere_ovf_vm_template.ovfRemote.remote_ovf_url
    disk_provisioning         = data.vsphere_ovf_vm_template.ovfRemote.disk_provisioning
    ovf_network_map           = data.vsphere_ovf_vm_template.ovfRemote.ovf_network_map
  }

  extra_config = {
    "guestinfo.talos.config"                   = base64encode(data.talos_machine_configuration.this.machine_configuration)
    "stealclock.enable"                        = "TRUE"
  }
}
