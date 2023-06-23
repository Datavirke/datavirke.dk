+++
title = "Bare-metal Kubernetes, Part III: Encrypted GitOps with FluxCD"
date = 2023-06-24
draft = false
[taxonomies]
tags = ["kubernetes", "fluxcd", "sops", "gitops"]
+++

We've got an actually working cluster now that is relatively secure, but rebuilding it and keeping it up to date is going to be a real chore.

Storing things like machine configurations, Talos config files and network policies in a git repository would help with the rebuilding part, but not with keeping it up to date. For that, we'll need some kind of continuous deployment system like [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) or [FluxCD](https://fluxcd.io/).

*Series Index*
* [Part I: Talos on Hetzner](@/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/index.md)
* [Part II: Cilium CNI & Firewalls](@/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/index.md)
* **[Part III: Encrypted GitOps with FluxCD](@/posts/bare-metal-kubernetes-part-3-encrypted-gitops-with-fluxcd/index.md)**
* Part IV: Ingress, DNS and Certificates
* Part V: Scaling Up
* Part VI: Persistent Storage with Rook Ceph
* Part VII: Private Registry with Harbor
* Part VIII: Self-hosted Authentication with Kanidm
* Part IX: Monitoring with Prometheus and Grafana
* Part X: Log collection
