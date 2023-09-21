terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.3.3"
    }

    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.4.3"
    }
  }

  required_version = ">= 1.5.3"
}

provider "talos" {}