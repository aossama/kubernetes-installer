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

4. Extract talosconfig file using terraform

    ```shell
   terraform output -raw talosconfig > /tmp/talosconfig
    ```

5. Export talosconfig file and extract kubeconfig
    ```shell
   export TALOSCONFIG=/tmp/talosconfig
   talosctl --nodes 10.0.140.21  kubeconfig /tmp/kubeconfig
    ```
   
6. Export kubeconfig file and use the cluster
    ```shell
   export KUBECONFIG=/tmp/kubeconfig
   kubectl get nodes
    ```
