+++
title = "Bare-metal Kubernetes, Part VIII: Containerizing our work environment"
date = 2023-08-26
draft = false
[taxonomies]
tags = ["kubernetes", "talos", "flux", "kubectl"]
+++

Setting up Kubernetes once is not *that* hard to get right. Where things usually start to go
wrong is when the cluster is left to its own devices for extended periods of time.

All of a sudden you're dealing with certificates expiring rendering your nodes unreachable,
and your workstation's package manager has dutifully updated all your cli tools to new versions
causing subtle, or even not-so-sublte, incompatibilities with the cluster or your workloads.

To get out ahead of some of these issues, and to get a good overview of the sprawling ecosystem
of tools we're using at the moment, I've decided to compile all of them into a singular docker
image, which can be upgraded as we go.

The final output of this post is available [here](https://github.com/MathiasPius/kronform/tree/main/tools)

## Picking a Base
I used to be a bit of an Alpine Linux fanatic. I still am, but I used to too. I have however
mellowed out a bit, and the trauma of dealing with all manner of OpenSSL, musl, and DNS-related
issues over the years, has meant that lately I've been reaching for debian's *slim* container
image whenever I've needed something to *just work*.

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
RUN mkdir -p /tools
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
we'll have to extract the binary from a tar.gz archive.

We repeat the above procedure for [talosctl](https://github.com/siderolabs/talos), [yq](https://github.com/mikefarah/yq),
[sops](https://github.com/getsops/sops) and [flux](https://github.com/fluxcd/flux2).

## Workspace Stage
With all our binaries rolled up into a nice little docker image, we can start configuring a *separate* image
which will be the one we will actually reach for, whenever we need to interact with the cluster.

Once again, we start from debian slim
```Dockerfile
FROM debian:bookworm-slim AS workspace
```

Running as root is of course considered *haram*. Perhaps more importantly, our repository will be cloned
onto our workstation itself and then mounted into the running container, which means that the files will,
nine times out of ten, be owned by our the default UID 1000. If we used a root container, any files we
created inside the container would automatically be owned by root, meaning if we exported a yaml manifest
or [kubectl cp (copied)](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#cp) a 
file from a container onto disk while inside our container, we would have to elevate privileged to access
it outside of the container. Apart from the the security implications, this is just plain tedious!

We'll configure a user with the clever name *user* inside the container with UID and GID 1000. That way
the owner id will be identical inside and outside of the container, and we can transition ourselves and
files seamlessly between them.

```Dockerfile
ARG UID=1000
ARG GID=1000

RUN groupadd -g ${GID} user
RUN useradd -M -s /bin/bash -u ${UID} -g ${GID} user
```

Once again we're using ARG, so we can set it once (and change it, if we happen to be 1001 for example) and
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

Finally, set the owner, so we actually assume the identity of this mysterious *user* when we `docker run`
the container:

```Dockerfile
USER ${UID}
```

## Keys to the Kingdom

Now, since we're using SOPS with GPG to manage secrets in our repository, we'll need to install GPG inside the
container, as well as a text editor of some sort in case we want to ever make changes while inside the container.

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

No big surprises, but we need to do some thinking when running the container.

First of all we'll need our repository code available. At least in its encrypted form:

```bash
[mpd@ish]$ docker run -it --rm -v $(pwd):/data tools:latest
```

Okay, that part didn't require much thinking, but this next part will: We'll need some way of accessing our GPG keys
inside of the container. By far the easiest way to do this, is to mount our own `$HOME/.gnupg` directory inside
the container, and then less intuitively, mounting `/run/user/$UID` as well. This will make the gnupg agent's
unix sockets available to the sops/gpg inside the container, effectively exposing the gpg environment on our
workstation.

Of course `/run/user/$UID` contains a lot more than just GPG sockets, so it would of course be preferable to be
able to just mount `/run/user/$UID/gnupg` and limit the exposure, but quite frankly... I can't figure out how to
make this work. I initially tried mounting just `/run/user/$UID/gnupg` which intuitively should work, but sops
throws back a GPG-related error alluding to `/home/user/.gnupg/secring.gpg` not existing, which is fair...
Except that clearly appears to be some kind of error of last resort, since mounting the entire `/run/user/$UID`
directory *does* work, yet produces no secring.gpg file.

I won't go as far as to endorse mounting the whole direcotry, but the container we're mounting this directory
into is about as lean as they come. There's a bare minimum of packages, and a handful of binaries. The odds of
a vulnerability existing in software, which is able to leverage this directory mount into some kind exploit is
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

# Incorporating our Credentials

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
