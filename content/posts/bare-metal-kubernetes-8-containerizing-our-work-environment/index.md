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
your workstation's package manager has dutifully updated all your cli tools to new versions
causing subtle, or even not-so-sublte, incompatibilities with the cluster or your workloads.

To get out ahead of some of these issues, and to get a good overview of the sprawling ecosystem
of tools we're using at the moment, I've decided to compile all of them into a singular docker
image, which can be upgraded as we go.

