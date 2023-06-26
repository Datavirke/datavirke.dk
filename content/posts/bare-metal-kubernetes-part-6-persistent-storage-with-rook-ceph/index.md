+++
title = "Bare-metal Kubernetes, Part VI: Persistent Storage with Rook Ceph"
date = 2023-06-27
draft = false
[taxonomies]
tags = ["kubernetes", "hetzner", "talos", "ceph", "rook", "storage"]
+++

If you've been following this series closely you might have seen the two extra hard drives with sizes ranging from 2-4TB on each of the provisioned nodes, totalling 6 disks and 16TB of capacity.

All that capacity is great, but it'd be even better if we could trade some of it for a few guarantees that it won't be gone temporarily when we upgrade a node, or forever the second one of our disks or nodes die.

[Ceph](https://ceph.com/en/) is a distributed storage system which takes raw *[JBODs](https://en.wikipedia.org/wiki/Non-RAID_drive_architectures)* and turns it into resilient networked storage.

[Rook](https://rook.io/) takes Ceph and wraps it in a neat little Kubernetes-friendly package, with a bow and everything!

In this post, I'll be deploying the Rook operators into our cluster and configuring a `CephCluster` as well as a block storage `CephBlockPool` which we can then use to fulfill `PersistentVolumeClaims` in our deployments.

*Series Index*
* [Part I: Talos on Hetzner](@/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/index.md)
* [Part II: Cilium CNI & Firewalls](@/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/index.md)
* [Part III: Encrypted GitOps with FluxCD](@/posts/bare-metal-kubernetes-part-3-encrypted-gitops-with-fluxcd/index.md)
* [Part IV: Ingress, DNS and Certificates](@/posts/bare-metal-kubernetes-part-4-ingress-dns-certificates/index.md)
* [Part V: Scaling Out](@/posts/bare-metal-kubernetes-part-5-scaling-out/index.md)
* **[Part VI: Persistent Storage with Rook Ceph](@/posts/bare-metal-kubernetes-part-6-persistent-storage-with-rook-ceph/index.md)**
* Part VII: Private Registry with Harbor
* Part VIII: Self-hosted Authentication with Kanidm
* Part IX: Monitoring with Prometheus and Grafana
* Part X: Log collection

Complete source code for the live cluster is available [@github/MathiasPius/kronform](https://github.com/MathiasPius/kronform)

# Considerations
Ceph is designed to host truly massive amounts of data, and generally becomes safer and more performant the more nodes and disks you have to spread your data across. While 3 nodes and 6 disks is a decent size for a hobby cluster, it barely registers in the world of Ceph as anything at all. That being said, I've used had Rook/Ceph running in a cluster of this size before and never experienced any problem, even though I broke several guidelines.