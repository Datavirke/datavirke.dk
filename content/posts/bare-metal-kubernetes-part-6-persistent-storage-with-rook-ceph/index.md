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
Ceph is designed to host truly massive amounts of data, and generally becomes safer and more performant the more nodes and disks you have to spread your data across. While 3 nodes and 6 disks is a decent size for a hobby cluster, it barely registers in the world of Ceph as anything at all. That being said, I've had Rook/Ceph running in a cluster of this size before and never experienced any problem, even though I broke several guidelines and fucked up the dreaded *placement group* number.

Trying to understand failures in a system as complex and *different* as Ceph is to a regular filesystem can be pretty daunting, and I wouldn't advise anyone to jump into the deep end if their livelihood depends on it. There are several much simpler solutions to this problem, especially if you're willing to go the managed route.

That being said, my experience with Ceph has been really good, and for my use case I have a strong enough grasp of Ceph to not experience data loss, and that's good enough for me.

# Setting up
Rook provides a handy [helm chart](https://github.com/rook/rook/blob/release-1.11/Documentation/Helm-Charts/operator-chart.md) for deployment with roughly a milion knobs for supporting all kinds of configurations, including accessing an external Ceph cluster. Most of these are not super important, and can be adjusted later when you find out you need to expose your storage as an [NFS](https://rook.io/docs/nfs/v1.7/) server, or what have you.

First we need a namespace to put our cluster and operator in. Since Ceph necessarily needs access to the host devices, we need to relax the security a bit, like we did with the ingress controller:
```yaml
# manifests/infrastructure/rook-ceph/namespace.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: rook-ceph
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
```
Next up is the rook operator deployment:
```yaml
# manifests/infrastructure/rook-ceph/rook-ceph.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: rook-release
  namespace: rook-ceph
spec:
  interval: 5m0s
  url: https://charts.rook.io/release
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  interval: 5m
  chart:
    spec:
      chart: rook-ceph
      version: ">=v1.11.0 <v1.12.0"
      sourceRef:
        kind: HelmRepository
        name: rook-release
        namespace: rook-ceph
      interval: 1m
  values:
    crds:
      enabled: true
    enableDiscoveryDaemon: true
```

This chart only deploys the *operator* however, and does not in fact turn your cluster into a Ceph cluster. For that, we need to first define a `CephCluster` custom resource.

## The Cluster
Defining the cluster is also relatively straight forward. Rook has a lot of example configurations both on their website and in their git repository which explain most of the configuration options, like how many *mons* you want. Of course you might have to check out the official Ceph documentation to find out what a *mon* even is.

I'll be using Rook's [Host Storage Cluster](https://rook.io/docs/rook/v1.11/CRDs/Cluster/host-cluster/) example as a template, since it is designed to work on hosts with raw devices, as opposed to itself consuming `PersistentVolumes`, for example.

```yaml
# manifests/infrastructure/ceph-cluster/cluster.yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v17.2.6
  dataDirHostPath: /var/lib/rook
  mon:
    count: 3
    allowMultiplePerNode: false
  dashboard:
    enabled: true
  storage:
    useAllNodes: true
    useAllDevices: true
  placement:
    all:
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
        operator: Exists
```
Monitors (or mons) are to Ceph as etcd is to Kubernetes. They're the arbiters of truth within the cluster. By opting to go with 3 of them spread across our nodes (again, like etcd), we can ensure some level of continued operation in the face of a temporary outage.

Dashboard gives us a handy overview over the critical pieces of the Ceph cluster and allows some configuration of our disks, or OSDs, as they're called in Ceph terminology.

For storage, we're electing to use all nodes and all attached devices. Of course Rook isn't Chaotic Evil, so it won't start formatting our Talos devices, but it will consume any all non-provisioned devices attached, which should be all 6 of the 2TB+ hard drives.

Since all our nodes are control-planes, we need to tell Rook to tolerate that.

With all these things set, we can push it to git and wait for Flux to roll it out.

```bash
[mpd@ish]$ kubectl run -it --rm \
    -n rook-ceph                \
    --image ubuntu:latest       \
    --privileged                \
    --overrides='{"spec": { "nodeSelector": {"kubernetes.io/hostname": "n2"}}}' \
    toolbox
```

Install gdisk, and use it to delete the drives.
```bash
[mpd@ish]$ apt update && apt install gdisk
```

Devices might be considered removable, which makes them ineligible for Ceph storage. Switch to `17.2.3`