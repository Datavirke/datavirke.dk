+++
title = "Project Lolemgug: Safe Composable Websites"
date = 2025-02-06
draft = false
[taxonomies]
tags = ["lolemgug", "rust", "wasm", "wordpress", "nextcloud", "sandbox"]
[extra]
toc = true
+++

I don't yet have all the answers for what shape this might take, but this post is an attempt at trying to force myself
to sit down and flesh some of it out.

## Motivations

* Existing runtime-configurable platforms are [vulnerable](https://wordpress.org), [slow](https://drupal.com), or have [questionable](https://nextcloud.com/) internal security management (non-sandboxed apps or access).
* Build-time configurable platforms are by their very nature [non](https://jekyllrb.com/)-[inter](https://gohugo.io/)-[active](https://www.getzola.org/), and require more than [basic](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site) [technological](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/getting-started-secure-static-website-cloudformation-template.html) knowhow to execute.
* Managed solutions are simultaneously [expensive](https://www.squarespace.com/pricing) and [proprietary](https://whatsquare.space/blog/how-to-create-a-squarespace-plugin) or [simply](https://simply.com) drop you on an ancient machine with noisy neighbours and leave you to your own devices.

## Innovations

Most of the solutions listed above were amazing technological feats at their inception, but a *lot* has changed, for better and worse. Security threats have grown in both scope and capability, but promising new technologies can help mitigate or side-step these risks.

### WASM

Though borne from the technological hellscape that is the Javascript ecosystem, the ability to sandbox and host applications or addons in locked down sandboxes without having to involve hardware virtualization is truly a game changer as far as writing securely extensible applications. Some projects have already taken this discovery and [run with it](https://extism.org/).

### Rust

The Original Sin of Wordpress and NextCloud is one that cannot be washed away: PHP. I understand the language may have come a long way in recent years, and that the overall quality of the PHP project is trending upwards, there is simply too much historical baggage and exposed API surface for it to keep pace with modern threat actors, barring monumental efforts.

It's important to note that only the security-critical Host platform would necessarily have to be written in Rust to achieve the level of assurance I think is necessary to trust software like this, but of course Plugins, though they could be written in anything compilable to WebAssembly, would no doubt benefit (as far as security & safety goes) from being written in Rust too.

### Capability-based security

Though hardly new, a [Capability-based security](https://en.wikipedia.org/wiki/Capability-based_security) framework in conjunction with a trusted Host system and subservient Plugin processes such as one built on WASM, could seriously limit the impact of compromised or vulnerable plugins, which I would wager is the most common attack vector for products like WordPress.

### Service Discovery

Cherry on top for a project like this, would be a means of service discovery, allowing seamless interaction and composability for plugins. Exposing persistent storage, whether Object or Relational, through interfaces which themselves might fulfill this contract through either remote or local means, would allow users to make the tradeoffs they want, for their specific use cases.

For some a simple Table interface based on sqlite might be sufficient, while others require Postgres with read replicas. Object storage can be handled by a filesystem host, an S3 gateway, or something else entirely.

Services might even be layered, by limiting interaction between these services. An example could be an encrypting object storage middleman, itself backed by Minio or a filesystem.

## Shaping the Ball of Mud

It's easy to throw all these things up in the air and imagine some utopian future where it all fits neatly together, but getting from here to there is sure to be fraught with obstacles and dead ends. I hope to uncover some of these in the early stages, by attempting to lay out my reasoning about how these pieces might fit together, no doubt rewriting this post a million times in the process.


# Goals

## 1. Security

It probably goes without saying, given the headlines above, but the biggest advantage of this solution over existing ones, would absolutely be *security*.

## 2. Usability

The safest program is one that never runs, but also a complete waste of time. Here, usability very specifically means "for non-technical users". The intended end user of this project is not a software developer, or even a self-taught computer "expert", usability should be targeting roughly the same ballpark as WordPress or NextCloud. It might not be possible for an end user to self-host either of these, but when dropped into it, they should be able to manage and customize it without intimate knowledge of software development.

## 3. Extensibility

Usefulness and appeal of WordPress is in large part to its plugin system, and the network effects of having one for almost any use case. This project should strive to replicate that success. The fact that even PHP can be compiled to WASM, means that compatibility layers might even be a feasible way of getting 80% of the way there very quickly, with the added bonus of sandboxing.

## 4. Interoperability

With WordPress and NextCloud, applications have zero Interoperability problems, since they all share both a database and codebase. With the security restrictions imposed by the first goal of this project, that part becomes a lot harder. Service Discovery and Cross-application API access will be the safest way to enable composition and code reuse, so a lot of thought needs to be put into its design.

The [WASM Component Model](https://component-model.bytecodealliance.org/design/why-component-model.html) might be the way to achieve this

# The Devil

Up until now, this has just been a handwavy wish list with completely uncontroversial choices.

In order for this post to be useful at all, we'll have to get into the weeds a bit. I've elected to do this by just jumping from topic to topic in whatever order they come to mind, to consider some of the potential obstacles I expect to hit, and how they might be circumvented.

