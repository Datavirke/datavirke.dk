+++
title = "Bare-metal Kubernetes, Part I: Talos on Hetzner"
date = 2023-06-22
draft = false
[taxonomies]
tags = ["kubernetes", "hetzner", "talos"]
+++

I've been running a Kubernetes cluster on a mix of virtual and bare metal machines with Hetzner for about a year now, and while the setup has served me well, being a very exploratory exercise at the time it wasn't very well documented.

To rectify this, and to get a chance to play with some tools I wasn't aware of at the time, I've decided to rebuild the cluster from scratch and document the process through these posts.

I have a rough sketch of the end product on my mind, which I plan to materialize through these steps/posts:

* **[Part I: Talos on Hetzner](@content/posts/bare-metal-kubernetes-part-1-talos-on-hetzner)**
    Covers provisioning of the first server, installation of Talos Linux and configuration of the first node.

* **Part II: Cilium CNI & Firewalls** Choosing a CNI and implementing network policies and firewall rules without locking ourselves out.

* **Part III: Encrypted GitOps with FluxCD** Keeping track of deployed resources, using [SOPS](https://github.com/mozilla/sops) to store secrets in the same repository.

* **Part IV: Ingress, DNS and Certificates** Installing an ingress controller (nginx), DNS controller (externaldns), and certificate manager for automating routing.

* **Part V: Scaling Up** A single node does not a cluster make! Time to scale the cluster up to 3 nodes

* **Part VI: Persistent Storage with Rook Ceph** With 3 nodes and 6 available disks, we're finally eligible to store data long term, which we'll need going forward.

* **Part VII: Private Registry with Harbor** Persistent storage allows us to store and cache the images we use, so let's!

* **Part VIII: Self-hosted Authentication with Kanidm** Using the root/admin credentials everywhere is easy, but not exactly secure. Using an OIDC-capable identity management solution we can hopefully switch most of our services to SSO.

* **Part IX: Monitoring with Prometheus and Grafana** We have a lot of workers and workloads, but very little insight into how they're performing. Let's fix that.

* **Part X: Log collection** Metrics are great for seeing *if* something is wrong, but logs helps to explain *why*.

---
