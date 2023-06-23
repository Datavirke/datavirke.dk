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


# Epilogue
[^1]: It looks like this has been fixed, at least as a beta-test [since 2.6](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/#helm-value-files-from-external-git-repository).

