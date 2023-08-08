resource "helm_release" "cilium" {
  name        = "cilium"
  chart       = "cilium"
  repository  = "https://nexus.aossama.net/repository/helm-cilium"
  namespace   = "cilium"
  version     = var.chart_version
  verify      = true
  create_namespace = true

  set {
    name  = "kubeProxyReplacement"
    value = "strict"
  }

  set {
    name  = "k8sServiceHost"
    value = var.cluster_host
  }

  set {
    name  = "k8sServicePort"
    value = var.cluster_port
  }

  set {
    name  = "tunnel"
    value = "vxlan"
  }

  set {
    name  = "ipam.operator.clusterPoolIPv4PodCIDRList"
    value = var.pod_networks
  }

  set {
    name  = "securityContext.privileged"
    value = "true"
  }

  set {
    name  = "socketLB.hostNamespaceOnly"
    value = "true"
  }
}