+++
title = "Bare-metal Kubernetes, Part IX: Renovating old Deployments"
date = 2024-04-24
draft = false
[taxonomies]
tags = ["kubernetes", "talos", "renovate", "day-2"]
+++

<i>Discussion on <a href="https://news.ycombinator.com/item?id=37443404">Hacker News</a></i>

As of writing this, my cluster has been up and running [mostly](@/posts/bare-metal-kubernetes-first-incident/index.md) as expected for 300 days!

During this time I've made an effort to keep Talos and Kubernetes somewhat up to date, as well all the different helm charts and kustomizations running within it, whenever I stumbled on an out of date version. This has worked reasonably well, primarily because of the small scope of the project, but it'd be real nice to *automate* this process. That way I get to stay up to date with all the developments, and don't accidentally leave a piece of critical infrastructure to fester in some corner, collecting CVEs.

The easiest way to go about this, as far as I am aware, is with [Renovate Bot](https://docs.renovatebot.com/). In short, it looks at all your dependencies (or deployments in this case) and compares each of their versions to what the latest one is, opening issues and pull requests with versions bumps to make upgrading as easy as possible.

The helm chart we'll be using is available [here](https://github.com/renovatebot/helm-charts/tree/main/charts/renovate).

*Series Index*
* [Part I: Talos on Hetzner](@/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/index.md)
* [Part II: Cilium CNI & Firewalls](@/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/index.md)
* [Part III: Encrypted GitOps with FluxCD](@/posts/bare-metal-kubernetes-part-3-encrypted-gitops-with-fluxcd/index.md)
* [Part IV: Ingress, DNS and Certificates](@/posts/bare-metal-kubernetes-part-4-ingress-dns-certificates/index.md)
* [Part V: Scaling Out](@/posts/bare-metal-kubernetes-part-5-scaling-out/index.md)
* [Part VI: Persistent Storage with Rook Ceph](@/posts/bare-metal-kubernetes-part-6-persistent-storage-with-rook-ceph/index.md)
* [Part VII: Private Registry with Harbor](@/posts/bare-metal-kubernetes-part-7-private-registry-with-harbor/index.md)
* [Part VIII: Containerizing our Work Environment](@/posts/bare-metal-kubernetes-part-8-containerizing-our-work-environment/index.md)
* **[Part IX: Renovating old Deployments](@/posts/bare-metal-kubernetes-part-9-renovating-old-deployments/index.md)**
* [Part X: Metrics and Monitoring with OpenObserve](@/posts/bare-metal-kubernetes-part-10-metrics-and-monitoring-with-openobserve/index.md)

Complete source code for the live cluster is available [@github/MathiasPius/kronform](https://github.com/MathiasPius/kronform)

## Personal Access Token

First thing we need is a personal access token which can access our repository. The required permissions for a token are listed [here](https://docs.renovatebot.com/modules/platform/github/#running-as-a-github-app), but since `Members` and `Checks` don't appear to be available, and I don't actually want it to create any workflows, I ended up with the following list:

| Permission        | Scope             |
|-------------------|-------------------|
| ~~Checks~~        | ~~read~~          |
| Commit statuses   | read + write      |
| Contents          | read + write      |
| Issues            | read + write      |
| Pull requests     | read + write      |
| Workflows         | read + ~~write~~  |
| Administration    | read              |
| Dependabot alerts | read              |
| ~~Members~~       | ~~read~~          |
| Metadata          | read              |

Take the granted token and shove it in a secret:
```yaml
# manifests/infrastructure/renovate/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: renovate-env
  namespace: renovate
type: Opaque
stringData:
  RENOVATE_TOKEN: "github_pat_ABABABABABABBABABABABABABABABBABABABABABABABABBABABABABABABABABBABAB"
```

We *could* throw the rest of our configuration into this secret as well, but since the rest of the options aren't actually, you know, secret, then I'll specify those in the renovate.config in the helm release below.

Don't forget to encrypt the secret!

```bash
sops -e -i manifests/infrastructure/renovate/secret.yaml
```


## Deployment

Configuring the `HelmRepository` and `HelmRelease` is exactly as easy as all the other times we did it, the only interesting parts here are the `renovate.config` fields, and specifying that we want the Renovate job to pull in our `renovate-env` secret.

```yaml
# manifests/infrastructure/renovate/renovate.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: renovate
  namespace: renovate
spec:
  interval: 5m0s
  url: https://docs.renovatebot.com/helm-charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: renovate
  namespace: renovate
spec:
  interval: 5m
  chart:
    spec:
      chart: renovate
      version: ">=37.0.0 <38.0.0"
      sourceRef:
        kind: HelmRepository
        name: renovate
        namespace: renovate
      interval: 1m
  values:
    renovate:
      config: |-
        {
          "extends": ["config:recommended"],
          "labels": ["renovate", "dependencies"],
          "platform": "github",
          "repositories": ["MathiasPius/kronform"]
        }
    envFrom:
      - secretRef:
          name: renovate-env
```


## Making it Go
With all that committed and deployed by Flux, we can trigger the Renovate cronjob just to get things going, instead of waiting till 01:00 in the morning.

```bash
$ kubectl create job --from cronjob/renovate renovate-1 -n renovate
```

And very soon after we receive a [Pull Request](https://github.com/MathiasPius/kronform/pull/4) from the Renovate bot. LGTM!


## The Curse of Being Built Different
One of the choices I made with this cluster which has been a perpetual pain in the ass, was overriding
the `cluster.local` default dns domain. As it turns out, a **LOT** of Kubernetes-packaged services assume this to be standard, and will cause them to fail in weird and
incomprehensible ways.

Luckily for us, the way it fails in Renovate's case is very comprehensible and even listed in their documentation: It simply pretends nobody would ever do anything as stupid as that, and doesn't take it into account when upgrading Flux.

The issue is covered by [this github issue](https://github.com/renovatebot/renovate/issues/13952), but that doesn't really help us, and looking at our very first (real) [Renovate PR](https://github.com/MathiasPius/kronform/pull/5), this would break our Flux deployment if merged!

Although this *kinda* feels like a loss, it actually just let us know that there's a new version of Flux available, so it's not too big of a chore to just deploy it manually. Let's not make this a habit though!

First thing we need to do is update our `tools` container with Flux 2.2.3:

```bash
# tools/Dockerfile
...
ARG FLUX_VERSION="2.2.3"
...
```

Then enter the container and re-generate the `gotk-components.yaml` file:

```bash
$ just tools
$ flux install --export                                                     \
  --cluster-domain=local.kronform.pius.dev                                  \
  --components-extra image-reflector-controller,image-automation-controller \
  > manifests/cluster/flux-system/gotk-components.yaml
```

This way our cluster domain is kept just the way we intended.. But oh so deeply regret.


## Expanding Scope
With that out of the way, let's expand the scope of Renovate a little, so it checks all our manifests for updates by adding the following to the config:

```json
"kubernetes": {
  "fileMatch": ["^manifests/.+\\.yaml$"]
},
"flux": {
  "fileMatch": ["^manifests/.+\\.yaml$"]
}
```

This way all yaml files in our `manifests/` directory are evaluated as possible flux/kubernetes and therefore tracked by Renovate.

I'm also tired of manually executing cronjobs, every time I make a change so let's bump the cronjob schedule to once every 5 minutes[^1],
and configure some decent security contexts for the job-pod while we're at it, giving us the final helm values as follows:

```yaml
values:
  cronjob:
    schedule: "*/5 * * * *"
  renovate:
    config: |-
      {
        "extends": ["config:recommended"],
        "labels": ["renovate", "dependencies"],
        "platform": "github",
        "repositories": ["MathiasPius/kronform"],
        "kubernetes": {
          "fileMatch": ["^manifests/.+\\.yaml$"]
        },
        "flux": {
          "fileMatch": ["^manifests/.+\\.yaml$"]
        }
      }
    securityContext:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
          - ALL
  envFrom:
    - secretRef:
        name: renovate-env
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
```

With all that configured, our renovate all of a sudden has a lot more work to do!

![Dependency Dashboard](dependency-dashboard.png)

Staying on top of updates is now as easy as keeping track of the periodically updated Dependency Dashboard issue and shooting off and merging PRs whenever a new version rolls around.

## Conclusion

Renovate let's you stop worrying about how much of your cluster is dangerously out of date, because it will literally tell you!

The fact that it makes it extremely convenient to do something about it too is just icing on the cake.

---

[^1]: I looked into setting up as well to make it super responsive, but the only tools for this I could find was [stack11/renovate-server](https://github.com/stack11/renovate-server), which doesn't appear to be actively maintained and therefore kinda flies in the face of the reasons why we're setting up Renovate in the first place. Also didn't appear to have any simple deployment options or pre-built container images.
