+++
title = "Bare-metal Kubernetes, Part IV: Ingress, DNS, and Certificates"
date = 2023-06-25
draft = false
[taxonomies]
tags = ["kubernetes", "talos", "ingress", "external-dns", "nginx", "cert-manager"]
+++
Let's reflect on the state of the cluster so far:

* Single node, which is chugging along beatifully.
* Cilium network policies protect our node from the onslaught of the internet.
* Our cluster secrets and administrator configs are stored encrypted in git, in case we need them.
* Flux helps to keep our software up to date, and our repository keeps an inventory of what we have deployed.

Our cluster is still relatively useless though, at least for deploying web applications. 

To fix that, we'll need:
1. An ingress controller, that can take incoming HTTP(S) connections and map them to services running in the cluster.
2. Cert-manager, which can retrieve and update certificates for our HTTPS resources.
3. External-dns, for managing our DNS records, so we don't have to.

*Series Index*
* [Part I: Talos on Hetzner](@/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/index.md)
* [Part II: Cilium CNI & Firewalls](@/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/index.md)
* [Part III: Encrypted GitOps with FluxCD](@/posts/bare-metal-kubernetes-part-3-encrypted-gitops-with-fluxcd/index.md)
* **[Part IV: Ingress, DNS and Certificates](@/posts/bare-metal-kubernetes-part-4-ingress-dns-certificates/index.md)**
* Part V: Scaling Up
* Part VI: Persistent Storage with Rook Ceph
* Part VII: Private Registry with Harbor
* Part VIII: Self-hosted Authentication with Kanidm
* Part IX: Monitoring with Prometheus and Grafana
* Part X: Log collection


# Choosing an Ingress Controller


# Certificate Manager



# External DNS