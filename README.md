# Kubernetes Installer

This repository contains IaC for provisioning Talos Kubernetes cluster on VMware vSphere.

## Quick Start

1. Install all required providers
    ```shell
    terraform init
    ```

2. Create a new terraform.tfvars file configuring it as required
3. Create the infrastructure

    ```shell
    terraform apply
    ```