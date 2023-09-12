+++
title = "Bare-metal Kubernetes, Part IX: Virtualization with Kata"
date = 2023-09-05
draft = false
[taxonomies]
tags = ["kubernetes", "talos", "kata", "kata-containers", "virtual machine", "vm"]
+++

Attempt to deploy virtual machines to Kubernetes using containerd and kata-containers

*Series Index*
* [Part I: Talos on Hetzner](@/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/index.md)
* [Part II: Cilium CNI & Firewalls](@/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/index.md)
* [Part III: Encrypted GitOps with FluxCD](@/posts/bare-metal-kubernetes-part-3-encrypted-gitops-with-fluxcd/index.md)
* [Part IV: Ingress, DNS and Certificates](@/posts/bare-metal-kubernetes-part-4-ingress-dns-certificates/index.md)
* [Part V: Scaling Out](@/posts/bare-metal-kubernetes-part-5-scaling-out/index.md)
* [Part VI: Persistent Storage with Rook Ceph](@/posts/bare-metal-kubernetes-part-6-persistent-storage-with-rook-ceph/index.md)
* [Part VII: Private Registry with Harbor](@/posts/bare-metal-kubernetes-part-7-private-registry-with-harbor/index.md)
* [Part VIII: Containerizing our Work Environment](@/posts/bare-metal-kubernetes-part-8-containerizing-our-work-environment/index.md)

Complete source code for the live cluster is available [@github/MathiasPius/kronform](https://github.com/MathiasPius/kronform)

# Building the extension

# Deploying a test cluster maybe? Qemu
