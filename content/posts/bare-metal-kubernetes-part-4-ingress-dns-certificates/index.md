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


# Ingress Controller
There are many excellent ingress controllers out there supporting a wide range of cases, but since our needs are pretty basic we'll just run with the official Kubernetes [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) controller, not to be confused with the other official [*NGINX* Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/)!

## Considerations
As mentioned in the [guide](https://kubernetes.github.io/ingress-nginx/deploy/baremetal/) there are some special considerations when deploying an(y) ingress controller to a bare-metal cluster.

Ingress controllers usually work by either exposing a `LoadBalancer` service which is picked up by the hosting provider's own controller, which provisions some sort of load balancer externally to the cluster and forwards the traffic to the cluster through a publically accessible port, usually in the range `30000-32767)`. Alternatively, the ingress controller can be configured with a `NodePort` service directly, and then a load balancer can be configured manually to forward to the exposed port.

Since we don't have a provider, or rather don't want to make use of Hetzner's Load Balancer service, that's not an option for us. We could theoretically still use a `NodePort` service, but telling people to *come visit my cool site at `https://example.com:32751`* is just not nearly as cool as being able to use the standard http(s) ports.

To achieve this goal, we're gonna have to be bad. But only a little bit. By running the ingress controller as a daemonset (that is, one instance per node exactly), and allowing it to run in the `hostNetwork: true`, we can let it listen on port `80` and `443` directly on the node, instead of using `NodePort`s. There are some security implications of this, like the ingress controller effectively getting localhost-access to the node, theoretically allowing it to interact with other services running on it. Since we're not running any unauthenticated services directly on the node anyway, and the software we're running is an official piece of Kubernetes software, I judge this risk to be very low.

Another somewhat orthogonal option would be to use a project like [MetalLB](https://metallb.org/) and Hetzner's vSwitch with a floating IP attached, which we could then reassign from node to node if one went down. Advantage of this would be that we could potentially rig the controller in such a way that it only gets access to the virtual VLAN ethernet link attached to the vSwitch, thereby separating it from the "real" node ethernet port. Whether this would actually provide any protection, or is even feasible I'm not sure.

Whatever the case, we won't explore this option for a couple of reasons:
1. Hetzner's vSwitch is limited to 1TB of traffic, with overruns costing extra.
2. Floating IP addresses are pretty expensive.
3. *Allegedly*, traffic running over vSwitch can sometimes be *worse* than just going through the hair-pinned public addresses of the nodes.
4. All traffic would flow through a single node at all times, instead of being spread out across the nodes.

The last point needs some exposition. By relying solely on DNS for load balancing, we're allowing incoming connections to be spread across all nodes, which is great. In most cases the target service will likely be a one-off, meaning the traffic would have to be routed between the nodes to reach the destination anyway, but this would be the same if using a floating IP. DNS Load Balancing might present a problem if a node goes down however, since even with low TTL and assuming all the intermediate caches respect it, we're probably still looking at upwards of 30 minutes of latency from our controller notices the node is down and issues the DNS update, to the time the end user's browser picks up a new address to try.

Enough excuses, let's get to work!

## Deploying the controller with a Flux
Just as with Cilium, we'll be using Flux's `HelmRepository` and `HelmRelease` resources to deploy the controller.

I'll allow myself to yada-yada over all the Kustomization shenanigans this time in the interest of brevity, but suffice to say that the procedure is exactly the same as with Cilium.

Create a namespace to hold our ingress controller
```yaml
# manifests/infrastructure/ingress-nginx/namespace.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
```

And the helm repository and release:
```yaml
# manifests/infrastructure/ingress-nginx/ingress-nginx.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 5m0s
  url: https://kubernetes.github.io/ingress-nginx

---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 5m
  chart:
    spec:
      chart: ingress-nginx
      version: ">=v4.7.0 <4.8.0"
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: ingress-nginx
      interval: 1m
  values:
    controller:
      hostNetwork: true
      hostPort:
        enabled: true
      kind: DaemonSet
```

Let's commit it and wait for Flux to do its thing.

The namespace gets created, as well as the `DaemonSet`, but there's no pod! Let's inspect the daemonset to see what's going on.

Running `kubectl -n ingress-nginx describe daemonset ingress-nginx` reveals a bunch of errors during pod creation:
```bash
Warning  FailedCreate      29s               daemonset-controller  Error creating: pods "ingress-nginx-controller-zdfff" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true), hostPort (container "controller" uses hostPorts 443, 80, 8443)
```
Oooh, right. Pod Security Policies are finally out and have been replaced with Pod Security Admissions, and in our talos machineconfig, we can see that the apiserver's default enforcement level is set to `baseline:restricted`:

```yaml
cluster:
  apiServer:
    disablePodSecurityPolicy: true
    admissionControl:
      - name: PodSecurity
        configuration:
          apiVersion: pod-security.admission.config.k8s.io/v1alpha1
          defaults:
            audit: restricted
            audit-version: latest
            enforce: baseline
            enforce-version: latest
            warn: restricted
            warn-version: latest
```
To be fair, I have been getting a lot of warnings when spawning other pods, but nothing that caused a disruption.

We could of course patch our machineconfig to disable the enforcement, but that seems like a really dumb thing to do. The policy is there to protect us after all, and we *are* doing some really dodgy things to be fair!

Instead, let's modify the `ingress-nginx` namespace to be a little more lenient:

```yaml
# manifests/infrastructure/ingress-nginx/namespace.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
```

Commit & Push and wait for the changes to take effect.

```bash
[mpd@ish]$ kubectl get pods -n ingress-nginx     
NAME                             READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-ksxvb   1/1     Running   0          2m36s
```
Gnarly! Let's see if we can get the nginx default page.

![Nginx default page timeout](nginx-timeout.png)

A timeout? Oooh, right. The *firewall!*

Let's add some HTTP and HTTPS rules to our `CiliumClusterWideNetworkPolicy` in `manifests/infrastructure/cluster-policies/host-fw-control-plane.yaml`:

```yaml
  # Allow HTTP and HTTPS access from anywhere
  - fromEntities:
    - world
    - cluster
    toPorts:
    - ports:
      - port: "80"
        protocol: "TCP"
      - port: "443"
        protocol: "TCP"
```

You might be wondering why I didn't just create a new `CiliumClusterWideNetworkPolicy` for this express goal to modularize the deployment a bit, and the reason lies in Cilium's enforcement strategy.

As mentioned in Part II, the default Cilium enforcement model does not restrict access unless a policy is actually applied to the endpoint. This means that if we create a separate policy just for HTTP and HTTPS and it somehow gets applied to the node *before* our other policy, then we will immediately lose access to all the important parts of the node like the Talos or Kubernetes API server. We'll of course retain access to he default nginx ingress page, but that's not worth a whole lot.

For this reason, and because there generally aren't that many rules to apply to nodes specifically, I like to keep it all in a single policy.

With that small aside out of the way, our policy will have had a chance to apply, so let's see if we can get a little further.

![nginx 404](nginx-404.png)

Great! This is exactly what we expect to see. After all, we haven't defined any ingress routes or anything yet, so the controller has nothing to serve us.

We'll wait with the full-scale test of ingresses till the end of this post. Next up is the cert-manager.

# Certificate Manager



# External DNS