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

# Choosing FluxCD
I've previously used ArgoCD for keeping helm releases up to date within a cluster, but they didn't support specifying helm values files in a separate directory from the chart, which effectively meant that if you needed to change *even a single value* of a chart, you had to basically create a new chart which had the original as a sub-chart and set the values that way.[^1]

FluxCD seems to solve this by having the helm values as part of the `spec` of their [`HelmRelease`](https://fluxcd.io/flux/components/helm/helmreleases/) resource, while also enabling some pretty cool integrations like [release promotion](https://fluxcd.io/flux/use-cases/gh-actions-helm-promotion/) out of the box.


# Installing FluxCD
The [Get Started with Flux](https://fluxcd.io/flux/get-started/) guide starts by declaring that you'll need GitHub credentials before continuing, but this is only because the guide targets GitHub, which is probably reasonable. Flux seems to work natively with the biggest [git servers](https://fluxcd.io/flux/components/notification/provider/), which is nice to know since we *might* want to move to a self-hosted git(ea|lab) instance at some point.


## Repository and Personal Access Token
I went ahead and created a (private for now) repository at [https://github.com/MathiasPius/kronform](https://github.com/MathiasPius/kronform), and embarked to configure a personal access token, as the guide requires. 

Unfortunately the documentation is really vague about which permissions are necessary, and as far as I can tell it isn't explicitly mentioned anywhere. Not being entirely sure about how Flux works internally, I went ahead and created a PAT with Read/Write access to most of the functionality on the just the one repository:

Read access to `kronform`: 
* metadata

Read *and* Write access to `kronform`:
* Dependabot alerts
* actions
* actions variables
* administration
* code
* commit statuses
* dependabot secrets
* deployments
* discussions
* environments
* issues
* merge queues
* pull requests
* repository advisories
* repository hooks
* secret scanning alerts
* secrets
* security events
* workflows 

## Bootstrapping
The easiest (and apparently) only way of installing FluxCD is through the `flux` cli, so I intalled it through my package manager. The latest available version was `2.0.0-rc.5`

Again, following the official guide exported my credentials:
```bash
[mpd@ish]$ export GITHUB_USER=MathiasPius
[mpd@ish]$ export GITHUB_TOKEN=github_pat_...
```

And ran the bootstrap command:
```bash
[mpd@ish]$ flux bootstrap github \
  --owner=$GITHUB_USER           \
  --repository=kronform          \
  --branch=main                  \
  --path=./manifests             \
  --personal
```
Everything went along swimmingly, until it seemed to hang while waiting for some Kustomizations to reconcile:
```bash
► connecting to github.com
► cloning branch "main" from Git repository "https://github.com/MathiasPius/kronform.git"
✔ cloned repository
► generating component manifests
# Warning: 'patchesJson6902' is deprecated. Please use 'patches' instead. Run 'kustomize edit fix' to update your Kustomization automatically.
✔ generated component manifests
✔ component manifests are up to date
► installing components in "flux-system" namespace
✔ installed components
✔ reconciled components
► determining if source secret "flux-system/flux-system" exists
► generating source secret
✔ public key: ecdsa-sha2-nistp384 AAAA...
✔ configured deploy key "flux-system-main-flux-system-./manifests" for "https://github.com/MathiasPius/kronform"
► applying source secret "flux-system/flux-system"
✔ reconciled source secret
► generating sync manifests
✔ generated sync manifests
✔ committed sync manifests to "main" ("be94c9fb726fcab7eb0aff77a0668be41f6f4429")
► pushing sync manifests to "https://github.com/MathiasPius/kronform.git"
► applying sync manifests
✔ reconciled sync configuration
◎ waiting for Kustomization "flux-system/flux-system" to be reconciled
# Process hangs here, and then fails below.
✗ client rate limiter Wait returned an error: context deadline exceeded
► confirming components are healthy
✔ helm-controller: deployment ready
✔ kustomize-controller: deployment ready
✔ notification-controller: deployment ready
✔ source-controller: deployment ready
✔ all components are healthy
✗ bootstrap failed with 1 health check failure(s)
```
Googling around I found some other people encountering the same issue, but the cause seemed to be something specific to OpenShift.

Using the `flux` cli to list the kustomizations explained exactly what went wrong though:

```bash
[mpd@ish]$ flux get kustomizations
NAME            REVISION        SUSPENDED       READY   MESSAGE
flux-system                     False           False   failed to download archive: GET http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/flux-system/be94c9fb.tar.gz giving up after 10 attempt(s): Get "http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/flux-system/be94c9fb.tar.gz": dial tcp: lookup source-controller.flux-system.svc.cluster.local. on 10.96.0.10:53: no such host
```
`.cluster.local`. That explains it. Flux assumes the dns domain of the cluster is `cluster.local` and requires us to override it in the bootstrap command. That decision is really just gonna keep coming back to bite me, isn't it?

Let's try again, with the correct cluster domain this time

```bash
[mpd@ish]$ export CLUSTER_DOMAIN=local.kronform.pius.dev
[mpd@ish]$ flux bootstrap github      \
  --cluster-domain=${CLUSTER_DOMAIN}  \
  --owner=$GITHUB_USER                \
  --repository=kronform               \
  --branch=main                       \
  --path=./manifests                  \
  --personal

...
◎ waiting for Kustomization "flux-system/flux-system" to be reconciled
✔ Kustomization reconciled successfully
```
Great, so far so good!

## Trying it out

The guide shows how to deploy `PodInfo` as an example project, so let's do that.

It uses the flux cli to generate the configurations, but the presented output documents are very legible, so we'll use those directly.

Let's just deploy the GitRepository and the Kustomization at the same time.
```yaml
# manifests/podinfo.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 30s
  ref:
    branch: master
  url: https://github.com/stefanprodan/podinfo
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kustomize
  prune: true
  sourceRef:
    kind: GitRepository
    name: podinfo
  targetNamespace: default
```
We push the yaml file and watch flux work:
```bash
[mpd@ish]$ flux get kustomizations --watch
```
After a short while, flux picks up our change and starts spamming updates, eventually ending with

```bash
NAME            REVISION                SUSPENDED       READY   MESSAGE                              
flux-system     main@sha1:d0bca4ce      False   True    Applied revision: main@sha1:d0bca4ce
podinfo         master@sha1:e06a5517    False   True    Applied revision: master@sha1:e06a5517
```

Using `kubectl` to check our default namespace we can see the `podinfo` service up and running:
```bash
[mpd@ish]$ kubectl -n default get deployments,services
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/podinfo   2/2     2            2           2m32s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
service/kubernetes   ClusterIP   10.96.0.1      <none>        443/TCP             161m
service/podinfo      ClusterIP   10.110.168.7   <none>        9898/TCP,9999/TCP   2m32s
```

Since we don't have an ingress controller yet (that's in part IV), we can't expose the service that way, so let's just proxy it from our local machine:

```bash
[mpd@ish]$ kubectl port-forward svc/podinfo 8080:9898
```

Navigating to `http://localhost:8080` in our browser it looks like it's working!

![PodInfo](podinfo.png)

Curious to see how Flux handles destructive actions and to clean up our test, I'll delete the `podinfo.yaml` from the `kronform` repository.

Sure enough, after a little while the deployment and service is yeeted out of the cluster, just as expected. 10 points to FluxCD.

## Restructuring
Reading over the [documentation for repository structure](https://fluxcd.io/flux/guides/repository-structure/), it looks like I might have bungled the setup a bit by yoloing the bootstrapping. This isn't critical, but it'd be nice to follow best practices, and the structure they suggest makes a lot of sense. Since I'll only be using the one cluster though, I decide to be a little bad and axe the `clusters/` sub-directory, instead opting to have just the one folder.

I couldn't find any documentation on how such a restructuring might happen, and the cli didn't provide any clues. Looking at the already deployed kustomizations generated during the bootstrap phase, the process seems pretty obvious. Here is `@kronform/manifests/flux-system/gotk-sync.yaml`:
```yaml
# This manifest was generated by flux. DO NOT EDIT.
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  secretRef:
    name: flux-system
  url: ssh://git@github.com/MathiasPius/kronform
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./manifests
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```
Theoretically, I should be able to just change that `path: ./manifests` line and move the entire directory, right?

Replacing the path with `./manifests/cluster` and moving `./manifests/flux-system` to `./manifests/cluster/flux-system` and committing the changes caused flux to simply update the deployed resources and continue on as usual. Awesome! Another 10 points to FluxCD.

# Backporting Cilium
Now that Flux is setup, let's get to work backporting our manually setup Cilium deployment from the previous post.

We'll start by creating the directory `manifests/infrastructure/cilium` and putting a `repository.yaml` file in there, with the following contents:
```yaml
# manifests/infrastructure/cilium/repository.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: cilium
  namespace: kube-system
spec:
  interval: 5m0s
  url: https://helm.cilium.io/
```
And of course a `kustomization.yaml` file which references it:
```yaml
# manifests/infrastructure/cilium/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- repository.yaml
```

This should configure a Helm Repository within the `kube-system` namespace, but of course flux is not yet configured to even look in the  `manifests/infrastructure` directory, so just co,mitting this change alone won't do anything.

We'll need to first create `Kustomization` resource which instructs Flux to watch this sub-directory of our aleady configured `GitRepository`:

```yaml
# manifests/cluster/infrastructure.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./manifests/infrastructure
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

And of course add the reference to it in `manifests/cluster/kustomization.yaml`

At this point the pointer chasing is a little confusing, so let's summarize the file structure, from the `kronform` repository:

```bash
[mpd@ish]$ tree manifests 
manifests
├── cluster
│   └── flux-system
│       ├── gotk-components.yaml
│       ├── gotk-sync.yaml
│       ├── infrastructure.yaml
│       └── kustomization.yaml
└── infrastructure
    └── cilium
        ├── kustomization.yaml
        └── repository.yaml
```

Let's commit all of this and see if it worked.

```bash
[mpd@ish]$ kubectl get helmrepository -n kube-system
NAME     URL                       AGE   READY   STATUS
cilium   https://helm.cilium.io/   18m   True    stored artifact: revision 'sha256:4cc5a535ccd03271289373f39cc47eb94150679d37f5a9cd8cd3a2b71f93a668'
```
Sure enough, our helmrepository resource has been created, which proves that the whole setup works end to end.

Of course we haven't fully back-ported the Cilium deployment until we've subsumed the helm release using flux, so let's do that next by translating our helm install action from the previous post into a `HelmRelease` resource:

```yaml
# manifests/infrastructure/cilium/release.yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: cilium
  namespace: kube-system
spec:
  interval: 5m
  chart:
    spec:
      chart: cilium
      version: ">=1.13.0 <1.14.0"
      sourceRef:
        kind: HelmRepository
        name: cilium
        namespace: kube-system
      interval: 1m
  values:
    ipam:
      mode: kubernetes
    hostFirewall:
      enabled: true
    hubble:
      relay:
        enabled: true
      ui:
        enabled: true
      peerService:
        clusterDomain: local.kronform.pius.dev
    etcd:
      clusterDomain: local.kronform.pius.dev
    kubeProxyReplacement: strict
    securityContext:
      capabilities:
        ciliumAgent:
        - CHOWN
        - KILL
        - NET_ADMIN
        - NET_RAW
        - IPC_LOCK
        - SYS_ADMIN
        - SYS_RESOURCE
        - DAC_OVERRIDE
        - FOWNER
        - SETGID
        - SETUID
        cleanCiliumState:
        - NET_ADMIN
        - SYS_ADMIN
        - SYS_RESOURCE
    cgroup:
      autoMount:
        enabled: true
      hostRoot: /sys/fs/cgroup
    k8sServiceHost: api.kronform.pius.dev
    k8sServicePort: "6443"
```
Once again committing and pushing, we can shortly after see that the helm release timestamp has been updated:
```bash
[mpd@ish]$ helm ls -n kube-system
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART           APP VERSION
cilium  kube-system     12              2023-06-23 12:06:05.983931976 +0000 UTC deployed        cilium-1.13.4   1.13.4
```

## Restructuring - Again.
Next natural step would be to backport the `CiliumClusterWideNetworkPolicy` we set up to protect our node(s), but this presents a slight problem.

We're treating the entirety of `manifests/infrastructure` as one big "kustomization", which means we can't define dependencies within it. We can work around this problem by creating independent `Kustomizations` for each subdirectory of `manifests/infrastructure` instead. This means a bit more configuration, but since it's infrastructure it will likely not change a lot.

The fix is pretty simple, simply replace `manifests/cluster/flux-system/infrastructure.yaml` with `cilium.yaml`:
```yaml
# manifests/cluster/flux-system/cilium.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./manifests/infrastructure/cilium
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```
And replace the reference in `manifests/cluster/flux-system/kustomization.yaml`.

Committing and pushing the changes unfortunately yeets Cilium completely from the cluster. Using `flux events` shows pretty clearly why:

```bash
[mpd@ish]$ $ flux events                        
REASON                  OBJECT                          MESSAGE                                                                                                     
ReconciliationSucceeded Kustomization/flux-system       Reconciliation finished in 1.149107647s, next run in 10m0s                                                 
ReconciliationSucceeded Kustomization/infrastructure    Reconciliation finished in 83.547843ms, next run in 10m0s                                                  
Progressing             Kustomization/flux-system       Kustomization/flux-system/cilium created                                                                   
Progressing             Kustomization/flux-system       Kustomization/flux-system/infrastructure deleted                                                           
ReconciliationSucceeded Kustomization/cilium            Reconciliation finished in 110.014532ms, next run in 10m0s                                                 
Progressing             Kustomization/cilium            HelmRelease/kube-system/cilium configured                                                                  
                                                        HelmRepository/kube-system/cilium created                                                                  
ReconciliationSucceeded Kustomization/flux-system       Reconciliation finished in 1.139469736s, next run in 10m0s                                                 
ReconciliationSucceeded Kustomization/infrastructure    HelmRepository/kube-system/cilium deleted                                                                  
                                                        HelmRelease/kube-system/cilium deleted                                                                     
ReconciliationSucceeded Kustomization/infrastructure    Reconciliation finished in 27.026008ms, next run in 10m0s                                                  
```
The new `cilium` Kustomization is applied first, resulting in effectively a no-op for the `HelmRelease`, after which the old `infrastructure` kustomization is garbage collected, destroying the `HelmRelease` resource for both of them.

The problem is quickly fixed (and likely would have been automatically in time) by issuing:
```bash
[mpd@ish]$ flux reconcile kustomization cilium
```

In retrospect, it would have been smart to mark the `infrastructure` kustomization with `prune: false` to avoid garbage collection, but things turned out alright in the end anyway.

## Backporting our node policy
Somehow our `CiliumClusterWideNetworkPolicy` by the name `host-fw-control-plane` survived this whole ordeal, I suspect because Cilium doesn't necessarily clean up its CRDs when it gets removed.

Whatever the case, the policy is still not managed by flux, so let's do that now. The policy obviously depends on us having already deployed Cilium, or the resource type will be unknown to Kubernetes.

Fortunately, the [Kustomization](https://fluxcd.io/flux/components/kustomize/kustomization/#dependencies) resource has a [dependency tracking field](https://fluxcd.io/flux/components/kustomize/kustomization/#dependencies).

Unfortunately the field doesn't work across flux-managed resource types, meaning we can't define our policy as part of a `Kustomization` and tell it to wait on a `HelmRelease`

FORTUNATELY we can work around this limitation using a kustomization [healthcheck](https://fluxcd.io/flux/components/kustomize/kustomization/#health-checks) instead.

We start by writing `manifests/cluster/flux-system/cluster-policies.yaml`, with a health check on our Cilium `HelmRelease` in the `kube-system` namespace:

```yaml
# manifests/cluster/flux-system/cluster-policies.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster-policies
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./manifests/infrastructure/cluster-policies
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2beta1
      kind: HelmRelease
      name: cilium
      namespace: kube-system

```
And add it to the cluster kustomization.

Next, we create a new infrastructure sub-directory called `cluster-policies` and put our `host-fw-control-plane.yaml` file in there, unmodified, and add the following `kustomization.yaml` file in the same directory:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- host-fw-control-plane.yaml
```

As a precaution, before committing and pushing the change, I enable `PolicyAuditMode' once more on the node:

```bash
[mpd@ish]$ kubectl exec -n kube-system cilium-6zv78 \
  -- cilium endpoint config 555 PolicyAuditMode=Enabled
Endpoint 555 configuration updated successfully
```
Now let's push!

With Cilium re-deployed several *minutes* ago, the health check passes instantly:
```bash
[mpd@ish]$ flux events
LAST SEEN   REASON        OBJECT                          MESSAGE
48s Progressing   Kustomization/cluster-policies  Health check passed in 24.818222ms
8s  Progressing   Kustomization/cluster-policies  CiliumClusterwideNetworkPolicy/host-fw-control-plane configured
```

If we never had the need to store secrets in our cluster, we'd practically be done by now, but that's not the case.

Let's take a look at integrating FluxCD with [Mozilla SOPS](https://github.com/mozilla/sops)

# Epilogue
[^1]: It looks like this has been fixed, at least as a beta-test [since 2.6](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/#helm-value-files-from-external-git-repository).

