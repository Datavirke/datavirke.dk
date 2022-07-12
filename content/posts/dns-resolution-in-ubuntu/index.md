+++
title = "An eventually comprehensive guide to domain name resolution in Ubuntu"
date = 2022-07-12
draft = false
[taxonomies]
tags = ["systemd", "dns", "ubuntu", "nameserver", "domain name resolution"]
+++

**Disclaimer**: This article is a work-in-progress, so if you notice errors or confusing segments, please let me know so I can correct them, and hopefully at some point remove *eventually* from the title. While Ubuntu is specifically listed in the title, the information might be relevant for other distributions, especially `systemd` based ones.

# tl;dr
Check `/etc/resolv.conf` for any `nameserver` settings. If it's pointing at `127.0.0.53` (the `systemd-resolved` resolver service). Use `$ resolvectl status` to figure out what `systemd-resolved` is using as its upstream nameserver. It will most likely be getting this upstream nameserver from either:

1. [netplan](#netplan), which configures [systemd-networkd](#systemd-networkd) if you're on a default-configured Ubuntu Server in turn getting its nameserver configuration from DHCP. Some cloud images might override this setting and bake their own recursive resolvers into their images or provide them via default cloud-init scripts.

2. [NetworkManager](#networkmanager) if you're on Desktop, or if your `netplan` is configured with `renderer: NetworkManager`.

If `/etc/resolv.conf` is *not* pointing at `127.0.0.53`, your quest is most likely over. Barring funky per-device search domain settings, the `nameserver`(s) listed in `/etc/resolv.conf` are exactly where your queries will be sent.

If the above information was not helpful it's time to buckle up, cause this is gonna be a pretty confusing ride.

# The Landscape
Domain Name Resolution in Linux is a lively place sprawling with tools, cross-referencing configuration files, independent services and so many different ways of doing what basically boils down to a key-value look-up.

I've collected a [non-exhaustive list](#list-of-services-and-files) of some of the files, tools and services you might have to interact with in order to make sense of your world. This guide is not going to touch on all of them, but if you run into an issue not covered by this guide, going through this list and seeing if any of these are present on your system, might be a good place to start.

Trying to deduce after the fact which services might be contributing confusing nameserver configuration information into your `/etc/resolv.conf` is nigh impossible, unless you're an `lsof`-ninja, and have some way of replicating the write.

----
# Consumers - Who's asking?
The first step to determining who answers your queries, is figuring out exactly who's asking. Just because you ask `host` to look up `my-favorite-domain.com`, does not necessarily mean that this is the query that `host` passes on to the actual resolver. Depending on how your `/etc/resolv.conf` is configured, any number of wild things might happen to that domain before it hits a resolver, and might not even be the same when using different tools like `dig` or `nslookup`.

Exactly which hostname is even looked up depends on the tool you use, and the arguments that are passed to it. Consult the [Big Table of Questions](#query-comparison-table) to figure why some of your `host`  queries might come back as you expect, while `dig` for instance does not.

## Brief aside about nsswitch
Under the hood, most of these tools use [getaddrinfo(3)](https://linux.die.net/man/3/getaddrinfo), but how it determines the method by which to perform the lookup is defined in `/etc/nsswitch.conf`, specifically the line that starts with `hosts:`. Each element in this line points to a library on your system which is used to perform the lookup. 

For example `dns` indicates that a `libnss_dns.so`file exists in your systems library paths (usually `/lib/`), which provides the actual lookup functionality using the nameservers in `/etc/resolv.conf`. Other commonly used libraries are `files` which uses `/etc/hosts` for resolution, or `resolve` which uses `systemd-resolved` directly. The databases are tried in order until a result is found, or an error occurs.

### `$ nslookup`
The O.G. domain resolution utility. Has an interactive mode, that I don't think I've ever seen anyone use, but plenty of people fall into accidentally when trying to get a list of command options out. Eats terminal newlines upon exit (at least mine). Behaves in much the same way as `host`, except slightly more verbose. Is both `ndots`- and `search`-aware as far as `/etc/resolv.conf` goes, defaulting to treating any lookup without dots in it as a local one, and any lookups with dots as absolute ones. These can be overriden in interactive mode, or in `/etc/resolv.conf`, or in the non-interactive mode using the `-option` switch.

### `$ host`
Unless otherwise specified on the command-line will get its nameserver information from `/etc/resolv.conf`, and use that to query results. Just like `nslookup`, `host` is `ndots`- and `search`-aware and shares the same defaults.

### `$ dig`
Gets its nameserver information directly from `/etc/resolv.conf`, but supports (according to iself) a much wider range of operations than `host`. Notable differences between this and `host` is that `dig` by default will ignore search domains specified in `/etc/resolv.conf`, requiring you to add a `+search` flag to your command, if this is the behaviour you want. 

I suspect this particular difference of opinion between `dig` and `host` might have been the cause of its fair share of *"but it works on my machine!"*-exclamations throughout the years.

### `$ drill`
The (not so) new kid on the block, not installed by default in either Desktop or Server minimal installations, and instead provided by the `ldnsutils`-package. Comes with all the DNSSEC bells and whistles one could ever want. Like everyone else, this tool takes its orders from `/etc/resolv.conf` by default, but search domain is completely ignored, and there doesn't seem to be any flag for configuring it.

### `$ resolvectl query`
Queries the `systemd-resolved` resolver directly, instead of obtaining nameservers from `/etc/resolv.conf` which may or may not point at the `127.0.0.53` systemd-resolved internal resolver service. Note that in most cases, the reply from here will be identical to other services (ignoring search domain logic), since by default `systemd-resolved` will either be the provider or consumer of `/etc/resolv.conf`, which in most cases aligns the search path. See the [`systemd-resolved`](#systemd-resolved) section for more information.


# Providers - Then who answers?
Now that we have some idea how the questions are being posed as far as search domains go, we can start delving a bit deeper into how a query is actually answered.

### systemd-resolved
In a default-configured Ubuntu 20.04 LTS Server or Desktop installation, your DNS queries are most likely to be answered by `systemd-resolved` by way of the "stub resolver" defined in `/run/systemd/resolve/stub-resolv.conf` which lists `nameserver 127.0.0.53` as its only nameserver, the address the `systemd-resolved` resolver service (`/lib/systemd/system/systemd-resolved.service`) binds to.

`systemd-resolved` has four modes of operation, but figuring out which one its in, is relatively simple.

1. **Stub Resolver** (default): `/etc/resolv.conf` is symlinked to `/run/systemd/resolve/stub-resolv.conf`, a file which `systemd-resolved` populates with a single entry pointing to itself (as above), as well as search domains.
2. **Static**: `/etc/resolv.conf` is symlinked to `/usr/lib/systemd/resolv.conf`. This mode is identical to the one above with the one exception that search domains are not available.
3. **Bypass**: `/etc/resolv.conf`is symlinked to `/run/systemd/resolve/resolv.conf`, a file which is populated with the upstream nameserver configuration which `systemd-resolved` uses, effectively bypassing `systemd-resolved` altogether, querying the upstream resolvers directly.
4. **Consumer**: `/etc/resolv.conf` is not symlinked to any of the above files, which means `systemd-resolved` assumes it is managed by another package (like `NetworkManager`), and becomes a consumer of `/etc/resolv.conf` instead of the owner of it.

Source: [systemd-resolved.service#/etc/resolv.conf](https://manpages.debian.org/testing/systemd/systemd-resolved.service.8.en.html#/ETC/RESOLV.CONF)

>Exercise for the Reader: What happens if `systemd-resolved` is in the **Consumer** mode (that is, you've unlinked `/etc/resolv.conf` and written one yourself), but `/etc/resolv.conf` still only contains the `systemd-resolved` endpoint `nameserver 127.0.0.53`? Is it a consumer? A provider?


In most cases systemd-resolved will be the provider of the `/etc/resolv.conf` file, in either **Stub Resolver** or **Static** mode, which means we're no closer to figuring out our actual responses are coming from, or how we enforce usage of our own nameservers. For starters, we can use `$ resolvectl status` to get `systemd-resolved` to tell us which nameservers it believes to be the correct upstream ones, but not how it came about that information.

### netplan
`netplan`'s only purpose, is generating configuration files for other network services, such as [`systemd-networkd`](#systemd-networkd) (the default networking service in Ubuntu Server). 

Although present in Ubuntu Desktop, it's usually just configured to hand over control to `NetworkManager`. That being said, devices and connections configured in `netplan` under Ubuntu Desktop while using the `NetworkManager` renderer, will (as you might expect) export these connections to `NetworkManager`, making them visible in the interface or through the `nmcli`. Changing them there however would be pointless, as they would be reset after the next reboot, or after the next `netplan apply`.

`netplan` is configured through YAML-files located in `/etc/netplan/`

### NetworkManager
The default operating mode for `NetworkManager` is to take ownership of `/etc/resolv.conf` and to *also* push nameserver configuration settings from its connections directly to `systemd-resolved`. This is configurable using the `dns` and `systemd-resolved` configuration options described [here](https://networkmanager.dev/docs/api/latest/NetworkManager.conf.html).

The nameserver settings are derived from the active connections `NetworkManager` controls, the configuration for which can be found in `/etc/NetworkManager/system-connections/`. Some packages like `docker` specifies more dynamic connections, which can be found in `/run/NetworkManager/system-connections/`.

You can inspect `NetworkManager`s current configuration using simply `$ nmcli`.

### systemd-networkd
Like `NetworkManager`, `systemd-networkd` is a system service for managing network connnections themselves, and which can optionally share discovered (DHCP) or configured (static) DNS configurations with `systemd-resolved`. This means that if you're using `systemd-networkd` as your network connection manager and expect it to populate your nameserver configuration, you **must** also use `systemd-resolved`. It is of course possible to use `systemd-networkd` without `systemd-resolved` (no automatic nameserver discovery) or inversely `systemd-resolved` without `systemd-networkd` (like when using `NetworkManager` or another service for connection management).

Configuration files for `systemd-networkd` are primarily found in `/etc/systemd/network/`. Like `NetworkManager`, some programs might add per-boot configurations to the *run* counterpart: `/run/systemd/network`.

# Addendum 
Resources, lists, indices and other resources which might be relevant when debugging domain name resolution.
## List of Services and Files {#list-of-services-and-files}
I've tried to list some of the services, files and tools which are commonly used when configuring or troubleshooting domain name resolution, even if I don't explicitly cover them in this guide.
### Files
* [/etc/resolv.conf](https://www.man7.org/linux/man-pages/man5/resolv.conf.5.html)
* [/etc/systemd/resolved.conf](https://manpages.debian.org/testing/systemd/resolved.conf.5.en.html)
* [/etc/resolvconf.conf](https://manpages.ubuntu.com/manpages/trusty/man8/resolvconf.8.html)
* [/etc/nsswitch.conf](https://man7.org/linux/man-pages/man5/nsswitch.conf.5.html)
* [/etc/gai.conf](https://www.man7.org/linux/man-pages/man5/gai.conf.5.html)
* [/etc/netplan/*.yml](https://manpages.ubuntu.com/manpages/cosmic/man5/netplan.5.html)
* [/etc/hosts](https://man7.org/linux/man-pages/man5/hosts.5.html)
* [/etc/hostname](https://man7.org/linux/man-pages/man5/hostname.5.html)
* [/etc/dnsmasq.conf](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)
* [/etc/dhclient.conf](https://linux.die.net/man/5/dhclient.conf)

### Tools
* [resolvectl](https://manpages.debian.org/testing/systemd/resolvectl.1.en.html), formerly [systemd-resolve](https://manpages.ubuntu.com/manpages/bionic/man1/systemd-resolve.1.html)
* [dig](https://linux.die.net/man/1/dig)
* [drill](https://linux.die.net/man/1/drill)
* [host](https://linux.die.net/man/1/host)
* [nslookup](https://linux.die.net/man/1/nslookup)
* [dnsmasq](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)
* [dhclient](https://linux.die.net/man/8/dhclient)
* [nmcli](https://linux.die.net/man/1/nmcli)
* [netplan](https://helpmanual.io/man5/netplan/)

### Services
* [systemd-networkd](https://www.man7.org/linux/man-pages/man8/systemd-networkd.service.8.html)
* [systemd-resolved](https://manpages.debian.org/testing/systemd/systemd-resolved.service.8.en.html)
* [dhcpd](https://linux.die.net/man/8/dhcpd)
* [dnsmaqd](https://man7.org/linux/man-pages/man8/systemd-resolved.service.8.html)
* [NetworkManager](https://linux.die.net/man/8/networkmanager)


## Big Table of Questions {#query-comparison-table}
Below I've compiled a table of how different tools respond to queries when called with a number of different arguments, and how they respond to search domains specified in `/etc/resolv.conf`. 

The result of each test is either a pass (✅) which means that the returned IP-address of the query matches the A-record for `example.com` as queried directly against `1.1.1.1`.

| command, search domain --> | (none) | com | example.com |
|---------|--------|-----|-------------|
| `nslookup example` | ❌ | ✅ | ❌ |
| `nslookup example.com` | ✅ | ✅ | ✅ |
| `nslookup www` | ❌ | ❌ | ✅ |
| `nslookup www.example` | ❌ | ❌ | ❌ |
| `nslookup www.example.com` | ✅ | ✅ | ✅ |
| `nslookup -search example` | ❌ | ✅ | ❌ |
| `nslookup -search example.com` | ✅ | ✅ | ✅ |
| `nslookup -search www` | ❌ | ❌ | ✅ |
| `nslookup -search www.example` | ❌ | ❌ | ❌ |
| `nslookup -search www.example.com` | ✅ | ✅ | ✅ |
| `nslookup -search -ndots=2 example` | ❌ | ✅ | ❌ |
| `nslookup -search -ndots=2 example.com` | ✅ | ❌ | ✅ |
| `nslookup -search -ndots=2 www` | ❌ | ❌ | ✅ |
| `nslookup -search -ndots=2 www.example` | ❌ | ✅ | ❌ |
| `nslookup -search -ndots=2 www.example.com` | ✅ | ✅ | ✅ |
| `nslookup -search -ndots=3 example` | ❌ | ✅ | ❌ |
| `nslookup -search -ndots=3 example.com` | ✅ | ❌ | ✅ |
| `nslookup -search -ndots=3 www` | ❌ | ❌ | ✅ |
| `nslookup -search -ndots=3 www.example` | ❌ | ✅ | ❌ |
| `nslookup -search -ndots=3 www.example.com` | ✅ | ❌ | ✅ |
| `host example` | ❌ | ✅ | ❌ |
| `host example.com` | ✅ | ✅ | ✅ |
| `host www` | ❌ | ❌ | ✅ |
| `host www.example` | ❌ | ❌ | ❌ |
| `host www.example.com` | ✅ | ✅ | ✅ |
| `host -N=2 example` | ❌ | ❌ | ❌ |
| `host -N=2 example.com` | ✅ | ✅ | ✅ |
| `host -N=2 www` | ❌ | ❌ | ❌ |
| `host -N=2 www.example` | ❌ | ❌ | ❌ |
| `host -N=2 www.example.com` | ✅ | ✅ | ✅ |
| `host -N=3 example` | ❌ | ❌ | ❌ |
| `host -N=3 example.com` | ✅ | ✅ | ✅ |
| `host -N=3 www` | ❌ | ❌ | ❌ |
| `host -N=3 www.example` | ❌ | ❌ | ❌ |
| `host -N=3 www.example.com` | ✅ | ✅ | ✅ |
| `dig example` | ❌ | ❌ | ❌ |
| `dig example.com` | ✅ | ✅ | ✅ |
| `dig www` | ❌ | ❌ | ❌ |
| `dig www.example` | ❌ | ❌ | ❌ |
| `dig www.example.com` | ✅ | ✅ | ✅ |
| `dig +search example` | ❌ | ✅ | ❌ |
| `dig +search example.com` | ✅ | ✅ | ✅ |
| `dig +search www` | ❌ | ❌ | ✅ |
| `dig +search www.example` | ❌ | ❌ | ❌ |
| `dig +search www.example.com` | ✅ | ✅ | ✅ |
| `dig +search +ndots=2 example` | ❌ | ✅ | ❌ |
| `dig +search +ndots=2 example.com` | ✅ | ❌ | ✅ |
| `dig +search +ndots=2 www` | ❌ | ❌ | ✅ |
| `dig +search +ndots=2 www.example` | ❌ | ✅ | ❌ |
| `dig +search +ndots=2 www.example.com` | ✅ | ✅ | ✅ |
| `dig +search +ndots=3 example` | ❌ | ✅ | ❌ |
| `dig +search +ndots=3 example.com` | ✅ | ❌ | ✅ |
| `dig +search +ndots=3 www` | ❌ | ❌ | ✅ |
| `dig +search +ndots=3 www.example` | ❌ | ✅ | ❌ |
| `dig +search +ndots=3 www.example.com` | ✅ | ❌ | ✅ |
| `resolvectl query example` | ❌ | ✅ | ❌ |
| `resolvectl query example.com` | ✅ | ✅ | ✅ |
| `resolvectl query www` | ❌ | ❌ | ✅ |
| `resolvectl query www.example` | ❌ | ❌ | ❌ |
| `resolvectl query www.example.com` | ✅ | ✅ | ✅ |
| `resolvectl query --search=no example` | ❌ | ❌ | ❌ |
| `resolvectl query --search=no example.com` | ✅ | ✅ | ✅ |
| `resolvectl query --search=no www` | ❌ | ❌ | ❌ |
| `resolvectl query --search=no www.example` | ❌ | ❌ | ❌ |
| `resolvectl query --search=no www.example.com` | ✅ | ✅ | ✅ |
| `resolvectl query --search=yes example` | ❌ | ✅ | ❌ |
| `resolvectl query --search=yes example.com` | ✅ | ✅ | ✅ |
| `resolvectl query --search=yes www` | ❌ | ❌ | ✅ |
| `resolvectl query --search=yes www.example` | ❌ | ❌ | ❌ |
| `resolvectl query --search=yes www.example.com` | ✅ | ✅ | ✅ |
| `drill example` | ❌ | ❌ | ❌ |
| `drill example.com` | ✅ | ✅ | ✅ |
| `drill www` | ❌ | ❌ | ❌ |
| `drill www.example` | ❌ | ❌ | ❌ |
| `drill www.example.com` | ✅ | ✅ | ✅ |


Above table generated using [this script](check.sh). Note that this script __will override your `/etc/resolv.conf` file and not restore it. Use only in disposable VMs!__

## Sources
1. [Linux man-pages](https://www.man7.org/linux/man-pages/index.html)
2. [Stéphane Graber's "DNS in Ubuntu 12.04" from 2012](https://stgraber.org/2012/02/24/dns-in-ubuntu-12-04/)
3. [StackOverflow answer by Zanna to DNS Resolution question from 2013](https://askubuntu.com/questions/368435/how-do-i-fix-dns-resolving-which-doesnt-work-after-upgrading-to-ubuntu-13-10-s)