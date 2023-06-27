+++
title = "Bare-metal Kubernetes, Part VII: Private Registry with Harbor"
date = 2023-06-27
draft = false
[taxonomies]
tags = ["kubernetes", "hetzner", "harbor", "proxy", "cache", "private registry"]
+++

Keeping track of all your dependencies can be extremely difficult. With modern packaging, distribution, and deployment methods enabling really fast iteration (as evidenced by this series), it's easy to build dependencies on all kinds of external services, without realizing it.

One *type* of dependency we're relying heavily on, is the presence of container registries for all our workloads. Even our [Linux/Kubernetes distribution](https://www.talos.dev/v1.4/reference/configuration/#installconfig) is built on container images! Being able to cache these images locally would be a nice insurance against network issues and registry outages, and for that we'll need a private registry with proxy caching, also known as a pull-through cache.

*Series Index*
* [Part I: Talos on Hetzner](@/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/index.md)
* [Part II: Cilium CNI & Firewalls](@/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/index.md)
* [Part III: Encrypted GitOps with FluxCD](@/posts/bare-metal-kubernetes-part-3-encrypted-gitops-with-fluxcd/index.md)
* [Part IV: Ingress, DNS and Certificates](@/posts/bare-metal-kubernetes-part-4-ingress-dns-certificates/index.md)
* [Part V: Scaling Out](@/posts/bare-metal-kubernetes-part-5-scaling-out/index.md)
* [Part VI: Persistent Storage with Rook Ceph](@/posts/bare-metal-kubernetes-part-6-persistent-storage-with-rook-ceph/index.md)
* **[Part VII: Private Registry with Harbor](@/posts/bare-metal-kubernetes-part-7-private-registry-with-harbor/index.md)**
* Part VIII: Self-hosted Authentication with Kanidm
* Part IX: Monitoring with Prometheus and Grafana
* Part X: Log collection

Complete source code for the live cluster is available [@github/MathiasPius/kronform](https://github.com/MathiasPius/kronform)

# How bad is it?
Before we go get into the nitty-gritty, let's take a second to see how dependent we actually are.

Using kubectl and some grep magic we can get a complete overview of all the images in use by our cluster, or rather all the pods currently deployed

```bash
[mpd@ish]$ kubectl get pod -A -o yaml | grep 'image:' | sort -u
image: docker.io/coredns/coredns:1.10.1
image: docker.io/rook/ceph:v1.11.8
image: ghcr.io/fluxcd/helm-controller:v0.34.1
image: ghcr.io/fluxcd/kustomize-controller:v1.0.0-rc.4
image: ghcr.io/fluxcd/notification-controller:v1.0.0-rc.4
image: ghcr.io/fluxcd/source-controller:v1.0.0-rc.5
image: k8s.gcr.io/external-dns/external-dns:v0.10.1
image: quay.io/ceph/ceph:v17.2.3
image: quay.io/cephcsi/cephcsi:v3.8.0
image: quay.io/cilium/cilium:v1.13.4@sha256:bde8800d61aaad8b8451b10e247ac7bdeb7af187bb698f83d40ad75a38c1ee6b
image: quay.io/cilium/hubble-relay:v1.13.4@sha256:bac057a5130cf75adf5bc363292b1f2642c0c460ac9ff018fcae3daf64873871
image: quay.io/cilium/hubble-ui-backend:v0.11.0@sha256:14c04d11f78da5c363f88592abae8d2ecee3cbe009f443ef11df6ac5f692d839
image: quay.io/cilium/hubble-ui:v0.11.0@sha256:bcb369c47cada2d4257d63d3749f7f87c91dde32e010b223597306de95d1ecc8
image: quay.io/cilium/operator-generic:v1.13.4@sha256:09ab77d324ef4d31f7d341f97ec5a2a4860910076046d57a2d61494d426c6301
image: quay.io/jetstack/cert-manager-cainjector:v1.12.2
image: quay.io/jetstack/cert-manager-controller:v1.12.2
image: quay.io/jetstack/cert-manager-webhook:v1.12.2
image: registry.k8s.io/ingress-nginx/controller:v1.8.0@sha256:744ae2afd433a395eeb13dc03d3313facba92e96ad71d9feaafc85925493fee3
image: registry.k8s.io/kube-apiserver:v1.27.2
image: registry.k8s.io/kube-controller-manager:v1.27.2
image: registry.k8s.io/kube-scheduler:v1.27.2
image: registry.k8s.io/sig-storage/csi-attacher:v4.1.0
image: registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.7.0
image: registry.k8s.io/sig-storage/csi-provisioner:v3.4.0
image: registry.k8s.io/sig-storage/csi-resizer:v1.7.0
image: registry.k8s.io/sig-storage/csi-snapshotter:v6.2.1
image: rook/ceph:v1.11.8
image: sha256:0631ce248fa693cd92f88ac6bc51485269bca3ea2b8160114ba7ba506196b167
image: sha256:88429d3e5d05e3805919a2958e002158e26da4ba73e4a8c894e2d5af066136c4
image: sha256:b555a2c7b3de8de852589f81b88381bec8071d7897541feeff65ad86d4be5e40
image: sha256:d00a7abfa71a66ef95c1e0bbe3ab1ecc08f24691f8479abbe16d802925869e6d
image: sha256:e901ba48d58c205d85e5116dc47be1d7e620a0b7cabbf83267a57592cf5ca739
image: sha256:ea299dd31352594c776cf1527b319fe3afb4b535bd9ba1e005a28983edf66330
```
37 different container images, and we haven't even finished laying the ground work yet! Being able to cache at least some of these images locally will help save both ourselves and their curteous hosts a decent amount of bandwidth, and make our setup a little more resilient, and with [Harbor](https://goharbor.io/) we even get a few nice bonuses like vulnerability scanning for free, which later on can help alert us when it's time to upgrade.

# Installing Harbor
Harbor has an official deployment helm chart located [here](https://github.com/goharbor/harbor-helm)


! Helm chart install


! Ingress admission hook?

! security policy - switch to bitnami

! update strategy


! proxy caches

! switch images to internal ones