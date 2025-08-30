---
title: "Bare-metal Kubernetes: First Incident"
date: 2023-08-01 08:00:00 CEST
tags: ["kubernetes", "talos", "harbor", "incident"]
---

I attempted to upgrade Talos from 1.4.6 to 1.4.7 and ended up completely breaking scheduling
across my cluster!

Here's how it happened:

1. Attempted to run talosctl upgrade from 1.4.6 to 1.4.7 for single node.
2. Forgot '--preserve' flag which I thought was required when upgrading clusters with rook[^1]
3. Aborted upgrade (CTRL+C). Node had not yet cordoned, but still went through with attempt.
4. Booted into 1.4.7. Then rebooted and rolled back to 1.4.6.

## Indication something was wrong
Ceph mgr dashboard temporarily showed 33% of capacity down as expected, but recovered.

After recovery cluster status still shows `HEALTH_ERR: MGR_MODULE_ERROR`, which claims 
that the Rook manifest object is "too old":

```json
{
    "type": "ERROR",
    "raw_object": {
        "kind": "Status",
        "apiVersion": "v1",
        "metadata": {},
        "status": "Failure",
        "message": "too old resource version: 7122415 (7123371)",
        "reason": "Expired",
        "code": 410
    }
}
```
<small>Some null fields omitted</small>

Listing pods in the `rook-ceph` namespace shows that some containers are failing to 
fetch images, showing state `ImagePullBackOff`, crucially the operator is one of them:

```txt
rook-ceph-operator-857f946667-qrhxm    0/1    ImagePullBackOff    0    96m
```

The image in question is `rook/ceph:v1.11.10`.

## Registry down
Checking on the Harbor registry, it seems that it is also failing to schedule for the
same reason. I suspect at this point that key harbor registry pods were running on
the node I had chosen to upgrade, which caused it to get rescheduled, but with the
registry down, the other nodes in the cluster were unable to fetch images.

I find this a bit curious, since I specifically configured fallback endpoints for just this contingency:

```yaml
mirrors:
  docker.io:
    endpoints:
      - https://registry.kronform.pius.dev/v2/docker.io
      - https://docker.io/v2
    overridePath: true
```

>"We'll also specify the actual endpoints in the mirror list, to act as a fallback
in case Harbor fails or needs an upgrade. It can't hardly pull images through itself!"
-- Me, less than a month ago.

The idea being that in case the registry goes down, talos/containerd would know to
just circumvent it and go straight to the source.

I can't seem to find any documentation covering this kind of fallback at the moment,
but I am positive, that this was how it was meant to work[^2].

Of course, it could be the case that the docker pull is *also* failing, perhaps due
to rate-limiting so I test it locally by pulling `rook/ceph:v1.11.10` directly from
Docker on my local machine to see if the rate limit has been hit, but it hasn't.
The image is pulled fine.

## Explicit override
Suspecting now that I have misunderstood Talos' registry mirror (assumed) fallback,
I edit the `MachineConfig` of the troubled node (so as to not disturb the now fragile
  Ceph or Etcd quorom), and remove the `docker.io` mirror config, since that should
  be enough to get Harbor running again, which should let us recover completely.

Killing some of the Harbor registry pods until they get scheduled on our troubled node,
does the trick... Sort of.

```bash
[mpd@ish]$ kubectl get pods -n harbor-registry                        
NAME                                  READY   STATUS                   RESTARTS   AGE
harbor-core-85fc4dbc9b-b8jb2            0/1   CrashLoopBackOff         34         106m
harbor-core-85fc4dbc9b-zxnmv            0/1   ContainerStatusUnknown   0          117m
harbor-jobservice-6f9df465-brc48        0/1   ImagePullBackOff         0          24h
harbor-notary-server-6fb45c475d-gwpsb   0/1   ContainerStatusUnknown   0          24h
harbor-notary-server-6fb45c475d-h7rbv   0/1   ImagePullBackOff         0          111m
harbor-notary-signer-6f5ccb769-lclgh    0/1   ContainerStatusUnknown   0          24h
harbor-notary-signer-6f5ccb769-wd259    0/1   ImagePullBackOff         0          111m
harbor-portal-5db68c6dd4-5h2x4          0/1   ImagePullBackOff         0          110m
harbor-portal-5db68c6dd4-dngb4          0/1   Completed                0          28d
harbor-portal-9f987766d-q25vs           0/1   ErrImagePull             0          3d15h
harbor-redis-master-0                   1/1   Running                  0          93m
harbor-registry-6488fd9ddc-gh4rv        2/2   Running                  0          105m
harbor-registry-6488fd9ddc-h8l59        0/2   ContainerStatusUnknown   0          24h
harbor-trivy-0                          0/1   ImagePullBackOff         0          24h
```
<small>I've shortened the pod names to fit them on screen</small>

Ignoring the `ContainerStatusUnknown`, attributing them to the less than graceful
shutdown of the node earlier, we see that `registry` and `redis` have
recovered from the ordeal, but the `core` service is still broken.

Checking the logs, reveals that it can't find the postgres database:
```txt
2023-07-29T12:36:24Z [ERROR] [/common/utils/utils.go:108]:
  failed to connect to tcp://harbor-registry-postgresql:5432,
  retry after 2 seconds :dial tcp 10.110.80.47:5432: connect: operation not permitted
```

And indeed, there are no postgresql databases running in the pod listing above.
Let's investigate.

## Harbor's Postgres
With our harbor helm chart configuration, harbor should deploy its own postgres database
as a `StatefulSet` and use it, so why isn't it running?

Describing the `harbor-registry-postgresql` set reveals the following:
```txt
Warning  FailedCreate  109s (x105 over 24h) statefulset-controller
  create Pod harbor-registry-postgresql-0 in StatefulSet harbor-registry-postgresql failed
  error: Pod "harbor-registry-postgresql-0" is invalid:
    spec.containers[0].env[4].valueFrom: Invalid value: "":
    may not be specified when `value` is not empty
```

Checking the statefulset, the error makes a lot of sense:
```yaml
- name: POSTGRES_PASSWORD
  value: not-secure-database-password
  valueFrom:
    secretKeyRef:
      key: postgres-password
      name: harbor-registry-postgresql
```

The password is being set in two different ways, which could obviously conflict, so the
statefulsets controller is blocking the pod creation.

Digging into the bitnami Harbor helm chart, it seems that it in turn leans on the bitnami
Postgres chart, which solved this [issue](https://github.com/bitnami/charts/commit/3bfcc0812171abc52f11edc32c2d31650a1bbc8c)
in `12.6.8` just a week ago, a bug which was introduced about
[a month ago](https://github.com/bitnami/charts/commit/d6234d8b8921470066e567832660164d84192975) in `12.6.2`.

Curiously, flux has been attempting to upgrade harbor's postgres to version `12.6.9`
and failing with that specific issue, which means the statefulset is still using the
old definition. The fact that the statefulset itself is 31 days old, suggests to me
that the statefulset is not actually getting upgraded. 

Editing environment variables in a StatefulSet is allowed, but it could be that the
deployment is also attempting to modify other parts of it unsuccessfully. I elected
to delete the statefulset at this point, hoping that our persistence settings will
allow the database to survive the ordeal. If not, reconfiguring the database is not
too big a task.

Using flux to suspend/resume the helmrelease deployment unclogs the setup, the
statefulset is recreated with the correct `POSTGRES_PASSWORD` secret, and the
postgres pod is deployed. Soon after the `core` service comes up.

With Harbor fully recovered, I change the troubled node's machineconfig back to the
way it was, allowing it to pull images primarily via the registry again. Of course
it takes a reboot to enact the change, and with Harbor still running on that node,
this won't end well at all.

## Back to Rook

Let's turn our heads back to Rook for a second. The operator is back up, and most
containers appear to be running, but our cluster health is still `HEALTH_ERR` because
the rook module failed. The manager pod has been running for 28 days at this point,
so the issue is probably because of the incident.

Killing the manager pod quickly spawns a new one, and the cluster status recovers,
at least according to Ceph. Rook is still complaining about the manager module crashing.

Rook also appears to be attempting to determine the ceph version but failing,
because it can't get a hold of the image `quay.io/ceph/ceph:v17.2.31`, and frankly
I can't either. Looking at [quay itself](https://quay.io/repository/ceph/ceph?tab=tags)
it seems like the newest version of the image at time of writing is `17.2.6`.
Is this a fluke?

I opt to delete both the batch job which tries to spawn this unknown image verison
and the operator itself, hoping this might somehow resolve the issue, but no luck.
Checking out the source code for the rook operator, I can't find any hardcoded
versions of this container, which means it must be coming from somewhere else.

Checking the logs of the new operator pod, something catches my eye:
```txt
2023-07-29 13:53:39.975016 E | ceph-nodedaemon-controller:
  ceph version not found for image "quay.io/ceph/ceph:v17.2.31"
  used by cluster "rook-ceph" in namespace "rook-ceph".
  attempt to determine ceph version for the current cluster image timed out
```
The image version is configured per-cluster, which means this is something *I* have set!
Sure enough, checking the kronform source code, I somehow managed to make a
[commit](https://github.com/MathiasPius/kronform/commit/8d902a5a63571823c2148d3771a7b1d0c68ceecd)
a month ago which broke this version tag, and with a commit message that did not at
all fit this particular commit too!

Changing the version tag back and pushing the changes finally resolves the rook problem.
Rook's operator is back in action and reconciling state like no tomorrow. So far so good!

## Root Causes
Let's go over what went wrong. Obviously I bodged the upgrade and my eagerness to abort
instead of having it play out might not have been great, so it was all just human error!

Well, if this was a 5-day outage in a production system run by a large international
financial IT systems provider, acting as the primary authentication provider for the six
million inhabitants of the small nation of Denmark for banking, pensions, health care and
child care, then I could've just chalked it up to [human error](https://www-nets-eu.translate.goog/dk-da/nyheder/Pages/Menneskelig-fejl-%C3%A5rsag-til-NemID-driftsforstyrrelse-i-juni.aspx?_x_tr_sl=da&_x_tr_tl=en&_x_tr_hl=en&_x_tr_pto=wapp) and gone about my day!

But this is a hobby Kubernetes cluster run for fun, so our standards are of course *way* higher.

There are a number of measures which could have prevented this incident:
1. **Misconfiguration of the registry mirrors caused fallback to fail.**

   As it turns out, setting `docker.io` as its own fallback seems to have been the cause of this.
   containerd did fall back to trying this, but for some reason hit against a `404 Not Found` issue,
   which it naturally accepted as "image does not exist" and stopped trying.
   
   I believe this might have something to do with Docker.io actually being a front for multiple registries,
   which together with the explicit selection of the `v2` API, sent the request somewhere it shouldn't.
   
   Removing the explicit fallback options has proven to allow nodes to fetch images from
   the source directly, in tests where the Harbor registry was unavailable.
   
2. **Harbor running in a standalone deployment mode, left no running registry when scheduling failed**.
   
   If I had been running Harbor as a high-availability deployment, it *might* have prevented
   the incident.
   
   I say might because high-availability deployments of postgres, one of
   the critical components of Harbor required by the core service, which in turn
   authorizes the pull requests from the nodes, are not trivial. From what I can
   gather from the [README](https://github.com/bitnami/charts/tree/main/bitnami/postgresql-ha/),
   it requires a single point of failure (SPOF) in the form of a gateway/proxy service to handle failover.
   
   Under normal circumstances and in a lot of failure cases this is completely legitimate.
   The proxy no doubt handles failover fast and gracefully, but it being a single point of
   failure in itself, means that if the node running it fails, it will have to be reschedule
   and will in all likelihood end up on a node which doesn't have the image preloaded.
   
   If our containerd fallbacks don't work, we'll be back to square one, The proxy will disappear
   and Harbor will have no way of contacting its "highly available" postgres deployment, meaning
   no way to authenticate image pulls, and therefore the node will have no way to schedule
   the proxy.
   
   The reason this might still have helped is that in scenarios where the proxy is already
   running on different node, this could have allowed graceful shutdown of the node running
   half of the harbor deployment. Since I was planning on upgrading the entire cluster, it
   would have eventually resulted in failure regardless.
   
3. **Lack of monitoring meant that the Rook version typo wasn't discovered earlier, making troubleshooting difficult**.
   
   Setting up proper monitoring and logging is in the pipeline, but hasn't been done yet. If it had,
   I might have noticed the issue with the rook ceph version being non-existent sooner either
   through Flux or Rook, which would have saved me a lot of confusion during this incident,
   and a lot of time during recovery.
   
## Corrective Measures
In the end, configuring the Talos/containerd fallbacks correctly gives me adequate confidence
that a catastrophic failure like this is unlikely to occur again.

With decent monitoring I hope to also limit the compounding complexity of attempting to sort through coincident issues.

Switching to a high availability deployment of Harbor is not worth the complexity, especially
not with the registry fallback now working as expected.

[^1]: As it turns out this is [only strictly necessary when using only a single `mon` instance](https://www.talos.dev/v1.5/kubernetes-guides/configuration/ceph-with-rook/#talos-linux-considerations)
      and since we have three, letting the upgrade go ahead would have been inconsequential. The flag is also always implicitly enabled since [1.8.0](https://github.com/siderolabs/talos/releases/tag/v1.8.0).

[^2]: I have not been able to find any such documentation, as far as I can tell, *nobody*
      does it this way, and in fact removing the explicit fallback, ended up fixing the
      issue. Sure seems like I just pulled it out of thin air in retrospect..
