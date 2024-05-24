+++
title = "Contemplating Entity Component Architecture"
date = 2024-05-22
draft = false
[taxonomies]
tags = ["ecs", "programmaing", "rust", "correctness"]
+++

Ever since discovering the [Entity Component System](https://en.wikipedia.org/wiki/Entity_component_system) pattern
through [Bevy](https://bevyengine.org/) a few years ago, I've been simultaneously obsessed with it and frustrated
with the lack of attention it is getting outside of the game development world.

Hopefully with this post (which I have been trying to write since at least May of 2023), I'll be able to move the
attention needle just a little bit in the right direction.

## What even is "Entity Component Systems"?

*Entity-Component-Systems* (ECS) is in theoretical terms a way of modelling a problem, the same way one might say
*Object-Oriented Programming* (OOP) is, and since most people are familiar with OOP, comparing the two might be
the easiest way to explain it.

Where OOP models the world as various *Objects*, encapsulating properties and behavior, ECS divorces the idea of some
concrete *object* from its properties, and the methods that act on them.

### Modeling Reality

One of the classical ways OOP is taught, is using the animal kingdom as a reference. 

1. You start by introducing an `Animal` base class which implements a method like `is_alive()`.

2. Inheriting from that, you create the `Mammal` class, implementing `lactate()` and `birth()`, then derive `Dog`.

3. On a roll you start modeling `Chicken`, inheriting from the [`Oviparous`](https://en.wikipedia.org/wiki/Oviparity) base class which implements `lay_egg()`.

Then you discover the platypus, and your whole world shatters.

### Entities & Components

Instead of looking at the world as a tree of strictly hierarchical abstractions like above, ECS gives taxonomy
the middle finger and embraces a pragmatic phenomenological view of the world, wherein ~~Objects~~ Entities
are merely collections of *Components*, which in turn are indivisible groups of properties.

In this world, there are no Cats, Dogs or Platypuses (as a means of convenience there [are](#archetypes), but
we'll get to that later), there are only *Entities* with some combination of `MammaryGland` (lactating), `Oviparous` (egg-laying) and `Viviparous` (live birthing) components.

Modeling the world in this open-ended fashion not only saves us the trouble of cranking out millions of object classes
in an attempt to describe the entire animal domain, it also allows us to maintain our sanity when we later discover that the [three-toed skink](https://www.sciencedaily.com/releases/2019/04/190402215619.htm) is simultaneously capable of live birth and egg-laying. Our world is *not* shattered, since there are no rules saying a given entity can't be both!

### Systems

It's just functions. Really. The beauty of them is that they act on components themselves and make no assumptions about
the entity to which they belong. In contrast to object methods, this makes them very robust because the reduced scope means
that the basic assumptions about a Component are far less likely to change [than that of an Object](https://en.wikipedia.org/wiki/God_object).

### Practical Applications

Okay so ECS could in theory be a powerful pattern when applied to large domains made up of complex entities with non-hierarchical or [convergent behaviour](https://en.wikipedia.org/wiki/Multiple_inheritance#The_diamond_problem), but I'm not making a farming simulator, so why does this help me? __Because the vast majority of software development takes place in exactly this kind of domain!__

Regulations change, your employer expands into new markets or functionality, or your largest client starts requiring unique functionality. In large or small ways, the domains within which we operate, as well as our understanding of them changes over time, and keeping this  in mind while defining the overall structure of our code is really important.

## Theoretically Intrigued, Practically Confused

At this point you're hopefully somewhat intrigued at the claims laid out above, but not at all convinced that I'm not just trying to sell you on something that sounds amazing right up until you have to put it into practice.

Let's set up an example using OOP and then see how we might have benefitted from designing our system in an ECS-like fashion instead.

### Onboarding at Congo

Welcome to Congo, the online marketplace named after the second largest rainforest in the world!

We've been in business for a few years at this point and this is how our backend is laid out:

```rust
/// Companies we get our products from
struct Supplier {
    name: String,
    incorporated_in: String,
    terminated: Option<DateTime>,
    email: String,
}

/// Individuals who make purchases on our platform
struct Customer {
    name: String,
    closed_account_at: Option<DateTime>,
    country: String,
    email: String,
}
```
<small>I'll be using Rust-like pseudo code for these code examples, but I'll try to keep it simple enough to follow, even if you've never used it before.</small>

Pretty clean, eh? Your first tasks are pretty simple:
 
1. **Aggressiland** has been sanctioned by our government, so we must break all relations with suppliers and customers from there.

2. **Northland** and **Southland** have formed a **Landian Union** and decreed that customer names must be removed *immediately* when a customer chooses to close their account, not just when the closure is final 30 days later.

3. **Southland** is celebrating a national holiday, *Celebratemas*, next week, so we should send out a personalized celebratory email to everyone it may concern.

Seems pretty daunting, but let's get to work:

```rust
fn implement_sanctions(
    suppliers: List<Supplier>,
    customers: List<Customer>,
) {
    for supplier in suppliers {
        if supplier.incorporated_in == "Aggressiland" {
            supplier.terminated = Some(Utc::now())
        }
    }

    for customer in customers {
        if customer.country == "Aggressiland" {
            customer.account_closed_at = Some(Utc::now())
        }
    }
}
```

Easy enough, next up, clearing out customer names:

```rust
fn landian_union_privacy_act(
    customers: List<Customer>,
) {
    for customer in customers {
        if customer.closed_account_at.is_none() {
            continue
        }

        if customer.country == "Soutland" 
        || customer.country == "Northland" {
            customer.name = ""
        }
    }
}
```

Almost there, but let's not celebrate prematurely:

```rust
fn celebrate_southland_holiday(
    suppliers: List<Supplier>,
    customers: List<Customer>,
) {
    for supplier in suppliers {
        if supplier.incorporated_in == "Southland" {
            send_celebratory_email(supplier.name, supplier.email)
        }
    }

    for customer in customers {
        if customer.country == "Southland" {
            send_celebratory_email(customer.name, customer.email)
        }
    }
}
```

All done... Or so you think, because when you present it for code review, you're informed of the following:

1. Emails to customers whose accounts have been scheduled for deletion, read `Dear <BLANK>, ...`.

2. Emails to suppliers start with `Dear <Company Name>, ...`, which isn't very personal at all!

2. The sanctions worked and **Aggressiland** released **Independistan**. which has joined the **Landian Union**.

3. In recognition of kinship with its liberators, **Independistan** also observes *Celebratemas* next week.

4. You forgot about the third type of relationship: `Clients`, which are other companies, who purchase from us in bulk:

    ```rust
    struct Client {
        company_name: String,
        operating_in: String,
        email: String,
    }
    ```

5. Some of our `Employees` also observe *Celebratemas*, and should receive emails as well!

    ```rust
    struct Employee {
        given_name: String,
        email: String,
        observes_celebratemas: bool,
        celebrates_pi_day: bool,
        observes_international_bee_day: bool,
        // ... and so on
    }
    ``` 

A few gray hairs sprout from your forehead.

<small>and your world shatters. *AGAIN!*</small>

### Componentmentalizing Congo

Let's rewind to your onboarding and switch to the alternate universe in which Object-Oriented Programming was never invented, and Congo was built firmly on an Entity Component System architecture.

This is our entire backend at the time of onboarding:

```rust
// Components of our backend
struct PersonalName(String);
struct CompanyName(String);
struct ContactEmail(String);
struct Terminated(DateTime);
struct Country(String);
```

Suppliers, Components, Clients and Employees no longer exist, which means we can't really just keep a `List` of each relation type.

Instead, we store all the *Components* in a structure like this:

```rust
// An "entity" is actually just a unique identifier.
type Entity = Uuid;

// This is starting to look a lot like database tables... More on that later!
struct Store {
    personal_names: Map<Entity, PersonalName>,
    company_names: Map<Entity, CompanyName>,
    contact_emails: Map<Entity, ContactEmail>,
    terminations: Map<Entity, Terminated>,
    countries: Map<Entity, Country>,
}
```

You'll note the complete absence of storage for entities. Entities are after all *just* the sum of their parts, so keeping track of entities alone makes no sense for our use case.

The pseudo-code implementation of `Store` looks like this:

```rust
impl Store {
    // Retrieve entity IDs and components matching a component signature
    fn list<Components>() -> List<(Entity, Components..)>;

    // Inserts a Component into the given Entity
    fn insert<Component>(entity: Entity, component: Component);

    // Removes the Component from the given Entity
    fn remove<Component>(entity: Entity);
}
```

Enough re-boarding, let's get to work.

### First day on the Job, again.

How might we achieve the our goals in this setup? Let's start with sanctions first:

```rust
fn implement_sanctions(
    store: Store
) {
    for (entity, country) in store.list<Country>() {
        if country == Country::Aggressiland {
            store.insert(entity, Terminated(DateTime::now()))
        }
    }
}
```

Okay that was pretty easy. Since we're operating on components instead of objects, we don't actually discriminate between suppliers and customers. It's all the same to us, which simplifies our implementation a lot. As an added bonus, this even works for the hitherto unknown class of relations we have with *Clients*!

Time to enact the privacy law.

We could do this the simple way and check the countries of our entities against the list of Landian Union members, but this means we'll need to modify the check in the future if someone joins or leaves the union, and if we have tens or even hundreds of pieces of functionality that depend on union membership, that's a hundred `if`-statements we need to change!

Let's instead utilize our ECS architecture to the fullest, and introduce a new component: `LandianUnionMember`.

Now, this component carries no actual data, it is just a *Marker*, its presence indicating that the entity in question is a member of the union, and of course its absence indicating non-membership.

```rust
// Our component. So pure!
struct LandianUnionMember;

struct Store {
    // Update our storage
    landian_union_members: Map<Entity, LandianUnionMember>;
    // ...
}
```

Implementing the privacy act in terms of this component is pretty simple:
```rust
fn landian_union_privacy_act(
    store: Store
) {
    // An iterator over all entities that satisfy the constraints:
    //   1. Is a LandianUnionMember
    //   2. Account is marked for closure
    //   3. Has a personal name
    let subjects = store.list<
        PersonalName,
        LandianUnionMember,
        Terminated
    >();

    // the LandianUnionMember and Terminated components are
    // simply ignored, since it is only their presence we care about.
    for (entity, personal_name, _, _) = subjects {
        store.remove<PersonalName>();
    }
}
```

For this to work we of course we also have to apply the marker to all countries we know to be members currently:

```rust
fn tag_landian_members(
    store: Store
) {
    for (entity, country) in store.list<Country>() {
        if country == Country::Southland
        || country == Country::Northland {
            store.insert(entity, LandianUnionMember)
        }
    }
}
```

Introducing the new component was a bit of a mouthful, but note that it had no consequences for our existing code base! We didn't have to update any existing database schemas, nor release a new version of our API to accomodate some new `is_landian_member` field of our Customer or Supplier objects.

This will also make tailoring functionality to landian union members extremely easy in the future. And of course if a country was to make the absurd choice of exiting the union in the future, we can simply remove the  `LandianUnionMember` marker.

Time to celebrate!

Like before, we add a new *Marker* trait, and apply it to all concerned parties

```rust
struct ObservesCelebratemas;

fn celebrate_southland_holiday(
    store: Store,
) {
    for (name, email) in store.list<PersonalName, Email>() {
        send_celebratory_email(name, email);
    }
}

fn tag_celebratemas(
    store: Store
) {
    for (entity, country) in store.list<Country>() {
        if country == "Southland" {
            store.insert(entity, ObservesCelebratemas);
        }
    }
}
```

Simple enough. Let's get it reviewed, and compare it to the feedback from last time:

1. ~~Emails to customers whose accounts have been scheduled for deletion, read `Dear <BLANK>, ...`.~~

    ✅ We only send emails to people with a `PersonalName`, but our privacy act implementation deletes this outright, so this does not apply to our ECS implementation.

2. ~~Emails to suppliers start with `Dear <Company Name>, ...`, which isn't very personal at all!~~

    ✅ We don't even use the company name, only `PersonalName` which can be assigned to a *Company* entity during sign up, to address it to our contact within the company

2. The sanctions worked and **Aggressiland** released **Independistan**. which has joined the **Landian Union**.

    Solution: add **Independistan** to our `tag_landian_members` system.

3. In recognition of kinship with its liberators, **Independistan** also observes *Celebratemas* next week.

    Solution: add **Independistan** to our `tag_celebratemas` system.

4. ~~You forgot about the third type of relationship: `Clients`, which are other companies, who purchase from us in bulk.~~

    ✅ No we didn't, we just don't care!

5. Some of our `Employees` also observe *Celebratemas*, and should receive emails as well!

    Solution: Add a checkbox which employees can check and thereby add the `ObservesCelebratemas` marker to their entities.




## Table Storage



## Archetypes

## Kubernetes
