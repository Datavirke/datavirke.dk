+++
title = "Entity Component Architecture"
date = 2023-05-15
draft = false
[taxonomies]
tags = ["ecs", "architecture", "monolith", "microservices", "kubernetes"]
+++

General concensus around [microservices](https://www.youtube.com/watch?v=y8OnoxKotPQ) seems to have settled on it being a measure of last resort, attempting to trade off the problems of organizational coordination and politicking at massive scales with the technical problems of software development and API contracts.

But if software development on the small or even individual level is more or less a solved problem (do whatever works for you!) and microservices are for giants, where does that leave, perhaps the largest demographic, the inbetweeners?

## Lessons not Learned

Object-Oriented Programming (OOP) tries to reason about the world through hierarchical inheritance with statements like *Cats are Mammals* and *Mammals give live birth* only to have its entire worldview destroyed by [Monotremes](https://en.wikipedia.org/wiki/Monotreme)[^1]. While OOP might be losing favor, objects still reign supreme. Even Kubernetes is built entirely on the foundations of clearly delineated Resources (Objects), which can reference each other, but *never* compose.

One of the appeals of microservices is requiring explicit boundaries around each service which, at least in theory, allows a determined developer to excise a well-scoped service and upgrading or replacing it if a deficiency is found, without chasing spaghetti, God-objects, and leaky abstractions across the entire business.

In practice of course this idea often falls on its face. Services are extremely hard to scope correctly, especially in a medium-sized business where almost all services fall squarely within the singular domain of whatever-the-company-produces.

Servicification increases the difficulty of committing these programming sins, but at the cost of much higher cognitive load[^2]. Worse still, if a highly motivated developer with the best of intentions and perhaps a deadline looming decides to take a shortcut, [Hyrum's Law](https://www.hyrumslaw.com/) ensures its permanence.

The appeal is obvious, but the remedy is backwards. The level of encapsulation must be *lowered*.

# Entities & Components

An alternative exists, and has seen widespread adoption in at least one industry: Games development. By doing away with classical Objects and instead regarding each Component part independently, you shrink the *unit of agreement* by an order of magnitude. In all likelihood, your program doesn't care which class of animal your cat or platypus belongs to, what it actually cares about, is whether it lays eggs.

in Entity Component architectures, in lieu of *Objects* with *Members*, gives you *Entities* with *Components*. An `Entity` by itself carries no information, except for a unique identifier. A `Component` contains just enough information to be useful, but should be kept extremely specific. Introducing a `Mammal` component at this point would make no sense.

What we can do instead is to look at the traits of the animals that we actually care about, like the sound it makes, or the number of legs it has. We can easily express this by introducing `Call` and `Legs` components:
```rust
struct Call(String);

// 4,294,967,295 might be a little overkill who knows,
// we might want to represent Millipedes in the future!
struct Legs(u32);
```

With these components we can construct cats, dogs (and even millipedes!):
  * A cat is just `Legs(4)` + `Call("Meow!")`.
  * Dogs are `Legs(4)` + `Call("Woof!")`.
  * millipedes have `Legs(1000)`, and no call![^3]

Now whenever a new cat is born or acquired, we just create a new entity with the necessary components.

At this point we've completely lost track of what dogs and cats are, but has any information of value been lost? If we poked either of these entities, we'd still be able to deduce the sound they made, if any. And if we wanted to buy them shoes, we'd know exactly how many to get. With this simple collection of components, we can easily introduce the platypus: `Legs(4)` + `Call("Purrr")`[^4].

Of course our simple model completely side-steps the issue OOP hit, so let's introduce two new components, `EggLaying` and `Nursing`:
```rust
struct EggLaying {
    in_utero_days: u8,
    external_days: u8
}

struct Nursing {
    weeks: u8
}
```

Now our entities look like this:
* Cats get `Nursing { weeks: 12 }`
* Dogs get `Nursing { weeks: 7 }`
* Platypus gets `Nursing { weeks: 12 }` *and* `EggLaying { in_utero_days: 28, external_days: 10 }`

With these components, and a few more concerning reproductive cycles, we can reason about population growth and egg production, without ever having to answer irrelevant questions about species. The beauty of this architecture is the minimal amount of assumptions that are baked in, and might therefore have to be ripped out later, and the de-duplication of code it allows for.

For instance, if we happend to acquire a chicken, we can easily represent that without having to modify any of our existing code, by just introducing a new entity and assigning it the components `Legs(2)`, `Call("Coo-coo-ca-chaa!")`, and `EggLaying { in_utero_days: 1, external_days: 21 }`.

Of course at this point it might make sense to disambiguate platypus and chicken eggs, by adding a `Species(String)` component or even just *marker*[^5] components like `Platypus` or `Chicken`. Keep in mind however, that you run the risk of consumers of these components making assumptions about them, and they might be tempted to implement egg-hatching functionality based on the species rather than the `EggLaying` component, which means that the functionality won't be generalizable to other egg-laying entities. In a few cases this is desirable, but it's a choice that should not be taken lightly.

## Systems

So far I've only talked about data, so before continuing let me quickly introduce *Systems*. If you've heard of Entities and Components before, it has no doubt been in the context of an Entity-Component-System (ECS) architecture. The "System" here is a little confusingly named, but just refers to any computation within this architecture which acts on entites and components. It could be a bash script, a Python lambda function, or just regular old function sitting in your webshop's or desktop application's codebase.

In our animal example above, you might introduce a "system" in a bash script that reads all `EggLaying` components from wherever the data is stored to make predictions about egg production capacity and emails it to a distributor.

I'll be using *system* to refer to any computation acting on entities and components, so if you want to visualise it as a function, module, library, docker container, lambda function, wasm blob, bash script, or microcontroller that's completely up to you.

# From Animal Kingdom to Business Domain

Egg-tracking is all well and good, but unless you're running a farm the example above is not very useful to you. Let's try to apply the same concept to some more relatable situations.

## Multi-cloud server administration
As we've seen above Entity-Component architecture lends itself well to situations where you're dealing with a multitude of "Objects" which, while similar, are not quite the same. If you're a technology company you probably have servers running both on-premises and with at least one cloud provider. Keeping them all up to date is a challenge which you might decide to solve programmatically.

Each of these instances are completely bespoke. AWS EC2 instances, Hetzner Cloud Servers and a Digital Ocean Droplets are all virtual machines, but they're structured very differently, and their design has built in assumptions about ip address assignment, operating system distribution naming, and so on.

Implementing a *Universal Operating System Updater* targeting all these disparate ecosystems is a massive challenge. The abstractions

But what if we implemented this in terms of an Entity Component architecture? First we identify the `Components` that we might actually care about:

* `IPAddress(IpAddr)`: The address we'll need to connect to.
* `SSHCredentials { username: String, fingerprint: String }`: Fingerprint is used for looking up the correct access key in our secrets management solution.
* `PackageManager(String)`: The package manager which will perform the update (apt, rpm, pacman).

A couple of things to note here.

* Operating System is nowhere to be found! How come? Well, we don't *really* care about the operating system or distribution, we just want to know which command we'll need to run to execute the update. Lots of distributions share package managers, so if we're running `apt update && apt upgrade -y`, do we really care if we're on Ubuntu or Debian?

* `IPAddress` is a little tricky. I haven't explicitly mentioned it, but in Entity Component architectures, the entity-component pairing is almost always unique, that is, you can't have many-to-one or one-to-many groupings between them. Attaching an `IPAddress` directly to the "server" entity keeps things simple, but might pose a problem if our server has more than one. The problem is easy to fix by moving the `IPAddress` to its very own entity, and introducing an `AssignedTo { server: Entity }` component, which allows us to express the one-to-many relationship that probably exists between servers and addresses.

  Another potential problem is that not all of those addresses are likely to be reachable via SSH. Introducing an `SSHAccessible` marker[^5] trait to the `IPAddress` entity itself solves this problem elegantly!

The problem space can now be broken down into the following systems:
1. Per-provider process for identifying Cloud Servers/EC2 Instances/Droplets and translating these into our previously defined components.

2. `PackageManager` identification process which acts on all entities which match the following signature:
    * Has `IPAddress`
    * Has `SSHCredentials`
    * Does not have `PackageManager`

    Uses the first two to connect and run some logic to deduce which package managers is installed, and then attaches a `PackageManager` component to the entity.

3. Per-package manager process for executing an update, e.g.: an apt updater which acts on `(IPAddress, SSHCredentials, PackageManager="apt")`.

   Marker traits could also be used in this case, but it complicates the package manager identification process, by forcing it to look for a perhaps unknown set of possible marker traits.

   A third way could be to simply encode the actual update command in the `PackageManager` component, simplifying the updater system at the cost of arbitrary code execution if the component database is compromised. This approach would also allow you to override the command on a per-host basis if you want to force reboots afterwards[^6] for example.

The beauty of this solution is that it *composes*! You can extend the above system in multiple directions without having to go back and rewrite functionality or engage higher-ups or coworkers for lengthy arguments about the exact phenomenological nature of what a *Server* or *Provider* is!

**Need to implement cost tracking to your entire fleet?** Introduce an `HourlyCost(Decimal)` component and have the provider systems backfill it as well as a `BusinessUnit(String)` component which links each server with the operator and then the rest is just statitics and reporting.

**Want to implement ssh key rotation?** You already have all the information you need! Just connect to each server and replace the `authorized_keys` file and update the database.

**Using bespoke software that needs to be updated as well?** You have access to the server already, just create a new entity with update instructions for your software and attach it to your server with `InstalledOn { server: Entity }` component, and then write your procedure for performing the update.

**Tired of servers updating and restarting in the middle of the workday?** Add scheduling by introducing the `ReadyToUpgrade` marker component which the updaters can look for, as well as an `UpgradeSchedule { window_start: DateTime, window_end: DateTime }` component which a new system can use to insert and remove the `ReadyToUpgrade` marker component.

**Got thrown off a server in the middle of a critical 04:00 debug session?** Update your scheduler to take active users into account or create a whole new system which deletes the `UpgradeSchedule` component if an incident has been reported, or just enables/disables the schedule with a marker component.


## Order Tracking
Moving on from the more operational side and into a common example given to let microservice architecture flex a little is order tracking in the context of a web shop. There are hundreds of ways you can slice the responsibility and functionality of a web shop, but usually it follows some form of BasketService, OrderService, ShippingService, each keeping track of its own piece of the journey and acting as the source of truth for its own domain.

In an Entity Component architecture, these discrete services make less sense. Instead of having a BasketService which keeps track of the user's shopping basket up until the point at which they place the order at which point the entire data set is transformed and handed off to the OrderService, you would simply:

1. Allocate an entity and grant it a `BasketOf{ customer_id: Entity }` component. This is our "Basket" entity, but as we'll see below it's not just a basket, it's also an order, a delivery note and a refund receipt.

2. From there entities are created whenever items are added to the basket, each line item containing a mix of:
`InBasket { basket: Entity }`, `Product { id: Uuid, quantity: u32 }`, `CouponCode(String)` (which can also apply to the basket itself!), and  of course `UnitPrice(Decimal)`.

3. With the customer done shopping, the website can prompt for delivery and payment options, assuming `CreditCard{...}` and `ShippingLocation{...}` is not already present on the "customer" entity referenced by `BasketOf`, of course!

4. After processing payment, the `ShippingLocation` is copied from the customer onto the "basket", and `OrderPlaced(DateTime)` as well as `PaymentComplete { refund_id: Uuid }` components are added to it. At this point this entity isn't really just a basket anymore, it's an *order*.

5. Entities with `ShippingLocation` and `OrderPlaced` components are automatically screened by fulfillment processes to see if the location matches the market they're designed to operate in (EU, UK, US).

6. The responsible fulfillment process adds a picking order to the nearest warehouse and starts printing shipping labels, adding the `BeingPickedBy { employee: Entity }` component. The entity is now no longer just an order, it's a direct work order used by warehouse employees.

7. Once the picker has collected the items, the `BeingPickedBy` component is replaced with `PickingFinished(DateTime)`, at which point shipping labels are printed based on the entity's `ShippingLocation` component.

8. Package is shipped, and a `Shipped(DateTime)` component is added. At every step of the way a process designed by a developer in customer system watches for `OrderPlaced`, `PickingFinished` and `Shipped` components, updating the customer along the way, by tracing the entity's `BasketOf` component back to the customer entity which of course contains an optional `EmailNotification(String)` component. A component which is populated by the team managing the customer profile section of the webshop.

9. A few days later the customer regrets his purchase and returns the package. The shipping id is mapped to the ~~Basket~~ ~~Order~~ ~~Shipping~~ Purchase entity,
and the `PaymentComplete` component's `refund_id` is used to trigger a refund with the payment provider, after which a `PaymentRefunded(DateTime)` component is added.

And hey presto! A complete and extremely composable webshop made of very loosely coupled processes which interface through simple components so small it's nearly impossible to argue about their format. Here's a rough sketch of the relationship between the different entities involved 

![Order Tracking Entity diagram](order-tracking.svg)

# Conclusion




# Caveats, Downsides & Pitfalls

* Component Spawl/Unknown unknowns -> Simplify
* Conflict (naming9 -> Be explicit
* Thrashing
* Versioning/Migration -> Simplify and up-front design
* Centralization -> Sharding?



# Addendum

* Processes (what are they)
* GraphQL
* Migration


## Notes

[^1]: [A helicopter is just a very advanced type of door.](https://twitter.com/lazerwalker/status/1654228460800471040)

[^2]: Who owns each service? How are they kept up to date? Who's responsible for breakages?

[^3]: Millipedes don't actually have exactly [a thousand feet](https://en.wikipedia.org/wiki/Millipede), and I find the idea of them screaming immensely terrifying.

[^4]: My best approximation of whatever [this](https://www.youtube.com/watch?v=dsd7ZfdZcNU) sound is.

[^5]: Marker components hold no information apart from their presence or absence, such as for example have an `Awake` component where its absence implies sleep.

[^6]: Again, this composes poorly and I'd consider it bad practice.