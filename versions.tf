terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.2.0"
    }

    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.4.1"
    }
  }

  required_version = ">= 1.5.3"
}

provider "talos" {}