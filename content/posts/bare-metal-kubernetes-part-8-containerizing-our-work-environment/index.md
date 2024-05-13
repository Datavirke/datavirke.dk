+++
title = "Bare-metal Kubernetes, Part VIII: Containerizing our Work Environment"
date = 2023-09-05
draft = false
[taxonomies]
tags = ["kubernetes", "talos", "docker", "container", "upgrade"]
+++

<i>Discussion on <a href="https://news.ycombinator.com/item?id=37443404">Hacker News</a></i>

Setting up Kubernetes once is not *that* hard to get right. Where things usually start to go
wrong is when the cluster is left to its own devices for extended periods of time.

All of a sudden you're dealing with certificates expiring rendering your nodes unreachable,
and your workstation's package manager has dutifully updated all your cli tools to new versions
causing subtle, or even not-so-sublte, incompatibilities with the cluster or your workloads.

To get out ahead of some of these issues, and to get a good overview of the sprawling ecosystem
of tools we're using at the moment, I've decided to compile all of them into a singular docker
image, which can be upgraded as we go.

*Series Index*
* [Part I: Talos on Hetzner](@/posts/bare-metal-kubernetes-part-1-talos-on-hetzner/index.md)
* [Part II: Cilium CNI & Firewalls](@/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/index.md)
* [Part III: Encrypted GitOps with FluxCD](@/posts/bare-metal-kubernetes-part-3-encrypted-gitops-with-fluxcd/index.md)
* [Part IV: Ingress, DNS and Certificates](@/posts/bare-metal-kubernetes-part-4-ingress-dns-certificates/index.md)
* [Part V: Scaling Out](@/posts/bare-metal-kubernetes-part-5-scaling-out/index.md)
* [Part VI: Persistent Storage with Rook Ceph](@/posts/bare-metal-kubernetes-part-6-persistent-storage-with-rook-ceph/index.md)
* [Part VII: Private Registry with Harbor](@/posts/bare-metal-kubernetes-part-7-private-registry-with-harbor/index.md)
* **[Part VIII: Containerizing our Work Environment](@/posts/bare-metal-kubernetes-part-8-containerizing-our-work-environment/index.md)**
* [Part IX: Renovating old Deployments](@/posts/bare-metal-kubernetes-part-9-renovating-old-deployments/index.md)
* [Part X: Metrics and Monitoring with OpenObserve](@/posts/bare-metal-kubernetes-part-10-metrics-and-monitoring-with-openobserve/index.md)

Complete source code for the live cluster is available [@github/MathiasPius/kronform](https://github.com/MathiasPius/kronform)

## Picking a Base
I used to be a bit of an Alpine Linux fanatic. I still am, but I used to too. I have however
mellowed out a bit, and the trauma of dealing with all manner of OpenSSL, musl, and DNS-related
issues over the years, has meant that lately I've been reaching for debian's *slim* container
image whenever I've needed something to just work.

Theoretically `debian:bookworm-slim`'s 74MB image size means that it's an order of magnitude
larger than `alpine:latest`'s meagre 7.33MB, but 74MB is still nothing, and if you're diligent
about pinning & pruning, that 74MB is stored exactly once, so who cares?!

```Dockerfile
FROM debian:bookworm-slim AS installer
```

## Structuring our Stages
Luckily for us, most of the tools we use are available as static binaries, which means we don't
have to deal with convoluted installation processes, and instead can just download the file and
be on our way. For this, we'll still need at least one tool: **curl** <small>(and also ca-certificates so we can use https)</small>

```Dockerfile
RUN apt-get update \
    && apt-get -y install --no-install-recommends ca-certificates curl \
    && apt-get clean
```

We'll need somewhere to put the files. We could install them directly into `/usr/local/bin` for
example, but we don't really need *curl* in our final image, so instead of trying to uninstall
the package once we're done, we'll just rewind the clock and use an entirely separate stage!

This way we can just copy over our downloaded files from our *installer* stage, and leave curl behind.

The advantage of this is that tools we add in the future might not be so simple to install, or
may even require building from source! In that case, we can clutter up the *installer* stage
with toolchains, makefiles, libraries, and what have you, and still be able to build a small
and shippable final image, without all the cruft.

Just to make copying from one stage to another easier down the road, we'll put all the binaries
in a single directory: `/tools`:

```Dockerfile
RUN mkdir /tools
WORKDIR /tools
```

## Collecting Binaries
With most of the prep done, it's time to actually get some tools. Let's start with `kubectl`
an absolute necessity for any Kubernetes administrator.

Checking the current version of our Kubernetes cluster shows that we're on `v1.27.4`:

```bash
[mpd@ish] $ kubectl version --short
Client Version: v1.27.4
Kustomize Version: v5.0.1
Server Version: v1.27.4
```

The kubectl binary can be downloaded directly from <https://dl.k8s.io/release/v1.27.4/bin/linux/amd64/kubectl>

But of course we won't be staying on that version for long. `1.27.5` and `1.28.1` has just been released,
so we will likely be migrating sooner rather than later. To make this easier, and to make it very easy
to see which version of each is included from the Dockerfile alone, we'll use `ARG`s to define the version:

```Dockerfile
ARG KUBECTL_VERSION="1.27.4"

RUN curl -L -o kubectl https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod u+x kubectl
```

Here we're downloading the binary directly, and marking it as executable for the owner. For other tools (such as flux),
we'll have to extract the binary from a tar.gz archive:

```Dockerfile
ARG FLUX_VERSION="2.1.0"

RUN curl -L -o flux.tar.gz https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz \
    && tar -xf flux.tar.gz \
    && rm flux.tar.gz \
    && chmod u+x flux
```

We repeat the above procedure for [talosctl](https://github.com/siderolabs/talos), [yq](https://github.com/mikefarah/yq),
[sops](https://github.com/getsops/sops).

## Workspace Stage
With all our binaries rolled up into a nice little docker image, we can start configuring a separate stage 
which will be the one we will actually reach for, whenever we need to interact with the cluster.

Once again, we start from debian slim
```Dockerfile
FROM debian:bookworm-slim AS workspace
```

Running as root is of course considered haram. Perhaps more importantly, our repository will be cloned
onto our workstation itself and then mounted into the running container, which means that the files will,
nine times out of ten, be owned by our the default UID 1000. If we used a root container, any files we
created inside the container would automatically be owned by root, meaning if we exported a yaml manifest
or [kubectl cp (copied)](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#cp) a 
file from a container onto disk while inside our container, we would have to elevate privileged to access
it *outside* of the container. Apart from the the security implications, this is just plain tedious!

We'll configure a user with the clever name *user* inside the container with UID and GID 1000. That way
the owner id will be identical inside and outside of the container, and we can transition ourselves and
files seamlessly between them.

```Dockerfile
ARG UID=1000
ARG GID=1000

RUN groupadd -g ${GID} user
RUN useradd -M -s /bin/bash -u ${UID} -g ${GID} user
```

Once again we're using ARG, so we can set it once (and change it, if I/you/we happen to be 1001 for example) and
reuse the ID in the directives to follow.

As mentioned, we'll be mounting the repository inside the container, so we'll need a directory. I've chosen
`/data` for no particular reason.

```Dockerfile
RUN mkdir /data && chown user:user /data
WORKDIR /data
```

Next, copy the binaries over from our installer stage and set the owner:

```Dockerfile
COPY --chown=user:user --from=installer /tools/* /usr/local/bin/
```

Finally, assume the identity of this mysterious *user* when we `docker run`
the container:

```Dockerfile
USER ${UID}
```

## Keys to the Kingdom

Now, since we're using SOPS with GPG to manage secrets in our repository, we'll need to install GPG inside the
container, as well as a text editor of some sort in case we want to ever make changes while inside.

```Dockerfile
ENV EDITOR=vim

RUN apt-get update \
    && apt-get -y install --no-install-recommends gpg $EDITOR \
    && apt-get clean
```

We'll get two birds stoned at once here by defining the `EDITOR` environment variable while we're at it. This way when
we want to edit encrypted files inside of our container using `sops myfile.yaml`, it'll default to using our selected
editor. Neat!

## Entering the Workspace

With our Dockerfile (final version available [here](https://github.com/MathiasPius/kronform/tree/main/tools)) setup,
it's time to build and see if everything works as intended.

```bash
[mpd@ish]$ docker build -t tools:latest tools/
```
<small>The Dockerfile we've been writing is located at tools/Dockerfile</small>

No big surprises, but we need to do some thinking when running the container.

First of all we'll need our repository code available. At least in its encrypted form:

```bash
[mpd@ish]$ docker run -it --rm -v $(pwd):/data tools:latest
```

Okay, that part didn't require much thinking, but this next part will: We'll need some way of accessing our GPG keys
inside of the container. By far the easiest way to do this, is to mount our own `$HOME/.gnupg` directory inside
the container, and then less intuitively, mounting `/run/user/$UID` as well. This will make the gnupg agent's
unix sockets available to the sops/gpg inside the container, effectively exposing the gpg environment from our
workstation.

Of course `/run/user/$UID` contains a lot more than just GPG sockets, so it would of course be to be
able to just mount `/run/user/$UID/gnupg` and limit the exposure, but quite frankly... I can't figure out how to
make this work.

I initially tried mounting just `/run/user/$UID/gnupg` which intuitively should work, but sops
throws back a GPG-related error alluding to `/home/user/.gnupg/secring.gpg` not existing, which is fair...
Except that clearly appears to be some kind of error of last resort, since mounting the entire `/run/user/$UID`
directory *does* work, yet produces no `secring.gpg` file.

I won't go as far as to endorse mounting the whole directory, but the container we're mounting this directory
into is about as lean as they come. There's a bare minimum of packages, and a handful of binaries. The odds of
a vulnerability existing in software which is able to leverage this directory mount into some kind exploit is
limited, even in the scope of our workstation.

The risk of it happening within our barebones container? Astronomical.

```bash
docker run -it --rm                       \
    -v $(pwd):/data                       \
    -v /run/user/1000/:/run/user/1000/:ro \
    -v $HOME/.gnupg:/home/user/.gnupg:ro  \
    tools:latest
```

A bit of a mouthful. At this stage I'd suggest either throwing this blurb into a script file so you don't have
to [wear out your up-arrow key](https://www.commitstrip.com/en/2017/02/28/definitely-not-lazy/?)

## Incorporating our Credentials

Up until now I've of course been using the `kubectl` and `talosctl` binaries installed on my host operating system,
which meant installing our kubeconfig and talosconfig files in my local home directory so they could find them.
Since everything is moving into the container now, those credential files have to move too.

The obvious thing to do, is to just mount the `~/.kube` and `~/.talos` directories directly, but this exposes
*all* our Talos/Kubernetes clusters to the container, not just the one we're operating on, and we have to mount
multiple directories.

Since talosconfig and kubeconfig already exist in an encrypted state in the repository, and we now have gpg & sops
configured within the container, a much cleaner approach would be to simply decrypt on the fly and install ephemeral
kube and talos configuration files *inside* the container.

This is easily achievable, by overriding the default `bash` entrypoint of the debian bookworm image.

First, create our decryption script `tools/entrypoint.sh`:

```bash
#!/usr/bin/env bash

mkdir /home/user/.talos
sops -d --input-type=yaml --output-type=yaml talosconfig > /home/user/.talos/config

mkdir /home/user/.kube
sops -d --input-type=yaml --output-type=yaml kubeconfig > /home/user/.kube/config

# Start the shell
bash
```

In all its simplicity, the script just decrypts and installs our configs, then hands over the reigns to bash.
Sops can work with arbitrary data, so the `--input-type` and `--output-type` options are necessary, to let it
now that the passed in files aren't fully encrypted, but actually just contain partially encrypted yaml. Usually
sops is smart enough to figure this out on its own, but since there's no `yaml` extension on either of the files
it needs a little  help.

Next, we need to obviously copy this script into the container image, and instruct Docker to execute it as the first thing:

```Dockerfile
COPY --chown=user:user --chmod=0700 entrypoint.sh /usr/bin/local/entrypoint
ENTRYPOINT ["/usr/bin/local/entrypoint"]
```

Now we won't even need to keep our credentials around on our machines. Sweet!

## Painless Updating
With all that in place, let's take our container for a spin!

The latest version of Talos is `1.5.1`, putting us a couple of versions behind, and ditto for Kubernetes. Let's start with Talos.

### Upgrading Talos

Luckily upgrading from `1.4.7` to `1.5.1` requires no special attention or at least none that affect us, however the only supported
upgrade path by Talos between minor versions is from latest patch to latest patch. This means that in order to arrive at `1.5.1`,
we have to take a detour to `1.4.8`, requiring a two-phase upgrade of `1.4.7 -> 1.4.8 -> 1.5.1`

Let's get to it!

We start by upgrading the version of talos installed in our container to the version we want to run. This isn't strictly necessary
to do at this point, since the `talosctl upgrade` command simply takes an container image and doesn't much care if the version we're installing
is behind or ahead, but by upgrading our local version first the default image to upgrade to will automatically be our target version,
meaning we won't accidentally fat-finger the procedure and initiate a rollback.

Change the version in our Dockerfile:
```Dockerfile
ARG TALOSCTL_VERSION="1.4.8"
```

Once rebuilt, we enter our container. I've written a [justfile](https://github.com/MathiasPius/kronform/blob/main/justfile)
for making it a little easier for myself. If you're not familiar with [Just](https://github.com/casey/just), you should be
able to glean what's going on from the link.

```bash
[mpd@ish] $ just tools
docker run -it --rm                         \
    -v $(pwd):/data                         \
    -v /run/user/1000/:/run/user/1000/:ro   \
    -v $HOME/.gnupg:/home/user/.gnupg:ro    \
    tools:latest
user@104e7ee67743:/data$ # And we're in!
```

Presented with our very anonymous "user" terminal, we'll kick off the upgrade procedure. Taking care to include the `--preserve` option,
so as to not repeat the massive blunder that was [The First Incident](@/posts/bare-metal-kubernetes-first-incident/index.md).

```bash
user@104e7ee67743:/data$ talosctl -n 159.69.60.182 upgrade --preserve
```
We don't have to include the `--image` option here, since it defaults to the version of our `talosctl`, which is already `1.4.8`

Talos does its thing, cordoning the node, upgrading Talos and booting into its upgraded version.

Let's see if everything is working as intended. Listing all our nodes, shows that the one node has indeed been upgraded:
```bash
user@104e7ee67743:/data$ kubectl get nodes -o wide
NAME   STATUS   VERSION   INTERNAL-IP     OS-IMAGE         KERNEL-VERSION
n1     Ready    v1.27.4   159.69.60.182   Talos (v1.4.8)   6.1.44-talos # <-- this one
n2     Ready    v1.27.4   88.99.105.56    Talos (v1.4.7)   6.1.41-talos
n3     Ready    v1.27.4   46.4.77.66      Talos (v1.4.7)   6.1.41-talos
```
Out of an abundance of caution, I also quickly log into the Ceph dashboard to check that all OSDs have recovered.

Next, we upgrade the remaining two nodes. Making sure that the cluster is healthy between each upgrade.

```bash
user@104e7ee67743:/data$ kubectl get nodes -o wide
NAME   STATUS   VERSION   INTERNAL-IP     OS-IMAGE         KERNEL-VERSION
n1     Ready    v1.27.4   159.69.60.182   Talos (v1.4.8)   6.1.44-talos
n2     Ready    v1.27.4   88.99.105.56    Talos (v1.4.8)   6.1.44-talos
n3     Ready    v1.27.4   46.4.77.66      Talos (v1.4.8)   6.1.44-talos
```
So far so good! Now at `1.4.8` across the board and no worse for wear we repeat the procedure, but this time wth `1.5.1`:
```Dockerfile
ARG TALOSCTL_VERSION="1.5.1"
```

And yadda, yadda, yadda...

```bash
user@e2029f39cf11:/data$ kubectl get nodes -o wide
NAME   STATUS   VERSION   INTERNAL-IP     OS-IMAGE         KERNEL-VERSION
n1     Ready    v1.27.4   159.69.60.182   Talos (v1.5.1)   6.1.46-talos
n2     Ready    v1.27.4   88.99.105.56    Talos (v1.5.1)   6.1.46-talos
n3     Ready    v1.27.4   46.4.77.66      Talos (v1.5.1)   6.1.46-talos
```

We're on `1.5.1`! At this point I manually edited the machineconfigs of each Talos node to `1.5.1`, just so they wouldn't
have to start from scratch at the the initial `1.4.6` in case of a potential rebuild in the future.

Next up, Kubernetes!

### Upgrading Kubernetes

Before upgrading Kubernetes, even between minor versions, you should always check out the list of deprecations
and changes, to see if it might interfere with any of your workloads!

As it turns out, the version of Cilium we're running (`1.13.6`) doesn't even support Kubernetes `1.28`, nor does
even the latest stable version! Kubernetes `1.28` support is only available in Cilium `1.15` which is a pre-release
version, so we'll have to settle for `1.27.5` for now.

No matter, a patch upgrade is still an upgrade.

Since `talosctl` will be doing the upgrading for us and we've already updated it, we're technically already set,
but like before it'd be great to be able to interact with the cluster directly after the upgrade from within the
container with a known-compatible client, so let's upgrade `kubectl` right away:

```Dockerfile
ARG KUBECTL_VERSION="1.27.5"
```

We rebuild the container once again and jump into it. This time we have to specify the target version, since talos
`1.5.1` by default assumes `1.28.0` is desired. We also do a dry run just as an extra precaution:

```bash
user@5fe767daf694:/data$ talosctl -n 159.69.60.182 upgrade-k8s --dry-run --to 1.27.5
```

Satisfied that this won't unleash hell on earth, we snip the `--dry-run` and go again:

```bash
user@5fe767daf694:/data$ talosctl -n 159.69.60.182 upgrade-k8s --to 1.27.5
```

Although we're explicitly selecting node `159.69.60.182` here, the `upgrade-k8s` command will automatically upgrade
the entire cluster, one piece at a time.


Once complete, make sure everything is in order:

```bash
user@5fe767daf694:/data$ kubectl get nodes -o wide
NAME   STATUS   VERSION   INTERNAL-IP     OS-IMAGE         KERNEL-VERSION
n1     Ready    v1.27.5   159.69.60.182   Talos (v1.5.1)   6.1.46-talos
n2     Ready    v1.27.5   88.99.105.56    Talos (v1.5.1)   6.1.46-talos
n3     Ready    v1.27.5   46.4.77.66      Talos (v1.5.1)   6.1.46-talos
```
v1.27.5 across the board, and all nodes ready. Looking good!

Finally, we update our local copies of the machineconfigs for our nodes, in case we need to recreate them,
using the handy [machineconfigs/update-configs.sh](https://github.com/MathiasPius/kronform/blob/main/machineconfigs/update-configs.sh) script,
and commit the new ones to git.

## Conclusion
This post went on a little longer than originally intended, but ended up providing (I would say) a good explanation of not only *how* to
containerize a Kubernetes-related work environment, but also a pretty decent demonstration of *why*, as exemplified by the extremely short
section dedicated to the upgrade procedure.

This post was initially inspired by a reader who ran into problems following a previous post, because I had completely failed to document
*which* version of each of the tools I was using, and not knowing there were multiple wildly different `yq`.

If nothing else, this post and the accompanying code changes in the GitHub repository, should provide a definitive reference, for anyone
else trying to follow along at home :)
