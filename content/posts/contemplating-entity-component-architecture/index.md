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

2. Inheriting from that, you create the `Mammal` class, which implements `lactate()`, then from it, derive `Cat`, `Dog`.

3. Seemingly on a roll you start modeling `Chicken` and `Duck`, both inheriting from the [`Oviparous`](https://en.wikipedia.org/wiki/Oviparity) base class, which implements `lay_egg()`.

Then you discover the platypus, and your whole world shatters.

### Entities & Components

Instead of looking at the world as a tree of strictly hierarchical abstractions like above, ECS gives taxonomy
the middle finger and embraces a pragmatic phenomenological view of the world, wherein ~~Objects~~ Entities
are merely collections of Components, which in turn are indivisible groups of properties.

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

Regulations change, the company expands into new markets or functionality, or your largest client starts requiring unique functionality. In large or small ways, the domains within which we operate, as well as our understanding of them changes over time, and keeping this  in mind while defining the overall structure of our code is really important.

## Theoretically Intrigued, Practically Confused

At this point you're hopefully somewhat intrigued at the claims laid out above, but not at all convinced that I'm not just trying to sell you on something that sounds amazing right up until you have to put it into practice.

Let's set up an example and see how ECS might allow us to evolve our and implement new features over time.

### Onboarding at Congo

Welcome to Congo, the online marketplace named after the second largest rainforest in the world!

We've been in business for a few years at this point and this is how our backend is laid out:

```rust
enum Country {
    Northland,
    Southland,
    Aggressiland,
}

/// Companies we get our products from
struct Supplier {
    name: String,
    incorporated_in: Country,
    email: String,
}

/// Individuals who make purchases on our platform
struct Customer {
    name: String,
    closed_account_at: Option<DateTime>,
    country: Country,
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
        if supplier.incorporated_in == Country::Aggressiland {
            delete_supplier(supplier)
        }
    }

    for customer in customers {
        if customer.country == Country::Aggressiland {
            delete_customer(customer)
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

        if customer.country == Country::Soutland 
        || customer.country == Country::Northland {
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
        if supplier.incorporated_in == Country::Southland {
            send_celebratory_email(supplier.name, supplier.email)
        }
    }

    for customer in customers {
        if customer.country == Country::Southland {
            send_celebratory_email(customer.name, customer.email)
        }
    }
}
```

All done... Or so you think, because when you present it for code review, you're informed of the following:

1. You're sending out emails to customers whose accounts have been scheduled for deletion, that read `Dear <BLANK>, ...`.

2. Emails to suppliers start with `Dear <Company Name>, ...`, which isn't very personal at all!

2. The sanctions already had an effect and **Aggressiland** granted independence to **Independistan**. which has joined the **Landian Union**.

3. In recognition of kinship with **Soutland**, **Independistan** also observes *Celebratemas* next week.

4. You forgot about the third type of relationship: `Clients`, which are other companies, who purchase from us in bulk.

    ```rust
    struct Client {
        company_name: String,
        operating_in: Country,
        email: String,
    }
    ```

5. Some of our `Employees` also observe *Celebratemas*
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

First of all, Suppliers, Components, Clients and Employees no longer exist. This is our entire backend at the time of onboarding:

```rust
enum Country {
    Northland,
    Southland,
    Aggressiland,
}

struct PersonalName(String);
struct CompanyName(String);
struct ContactEmail(String);
struct AccountClosed(DateTime);
```

Of course this means that we can't really just keep a `List` of each relation type, since we explicitly haven't defined terms like Client, Customer or Supplier.

Instead, we just keep all the *Components* in a structure like this:

```rust
// An "entity" is actually just a unique identifier.
type Entity = Uuid;

// This is starting to look a lot like database tables... More on that later!
struct Store {
    personal_names: Map<Entity, PersonalName>,
    company_names: Map<Entity, CompanyName>,
    contact_emails: Map<Entity, ContactEmail>,
    account_closure: Map<Entity, AccountClosed>,
}
```

You'll note the complete absence of storage for entities. Entities are after all *just* the sum of their parts, so keeping track of entities alone makes no sense.

The pseudo-code implementation of Store looks like this:

```rust
impl Store {
    // Returns a list of tuples where each tuple is made up
    // of an entity id, and the given components which belong to it
    // filtering out entities which do not have a corresponding component.
    fn list<Components>() -> List<(Entity, Components..)>;

    // Inserts a Component into the given Entity
    fn insert<Component>(entity: Entity, component: Component);

    // Removes the Component from the given Entity
    fn remove<Component>(entity: Entity);
}
```

How might we achieve the our goals in this setup? Let's start with sanctions first

```rust
fn implement_sanctions(
    store: Store
) {
    for (entity, country) in store.list<Country>() {
        if country == Country::Aggressiland {
            store.insert(entity, AccountClosed(DateTime::now()))
        }
    }
}
```

Okay that was pretty easy. Time to enact the privacy law.

We could do this the simple way and check the countries of our entities against the list of Landian Union members,
but this means we'll need to duplicate this conditional in the future if someone joins or leaves the union, and if we have tens or even hundreds of pieces of functionality that depend on union membership, that's a hundred `if`-statements we need to modify.

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
        AccountClosed
    >();

    // the LandianUnionMember and AccountClosed components are
    // simply ignored, since it is only their presence we care about.
    for (entity, personal_name, _, _) = subjects {
        store.remove<PersonalName>();
    }
}
```

But of course we also have to apply the marker to all countries we know to members currently:

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

Introducing the new component was a bit of a mouthful, but note that it had no consequences for our existing code base, and will make tailoring functionality to landian union members extremely easy in the future. And of course if a country was to exit the union in the future, we can simply compile a list of these and compare it against all entities which have the `LandianUnionMember` marker, removing them as we go along.



## Table Storage


















<br><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br /><br />
Todo-apps are often used to demonstrate technologies or patterns because the problem space is simple enough to wrap your head around, yet complex enough that you can take it as far as you like. 

### ToDoing it for real

Let's pretend-build a partial To-Do-app backend, and explore how ECS might affect the way we structure our program.

The best place to start something like this is to model the structure of what *exactly* a `Todo` is:

```rust
struct Todo {
    id: u32,
    text: String,
    done: bool,
}
```
<small>I'll be using Rust-like pseudo code for these code examples, but I'll keep it simple enough to follow, even if you've never used it before.</small>

This is a decent place to start! We have an `id` so we can direct actions at it through an API, like *delete* or *mark_as_done*, some `text`which explains what it is that needs doing, and of course a boolean flag to mark it indicate the state of the item.

Let's implement this API:

```rust
fn create_todo(todos: &mut Vec<Todo>, text: String) {
    let max_id = todos.iter().max(|todo| todo.id);

    todos.push(Todo {
        id: max_id + 1,
        text: text,
        done: false
    });
}

fn mark_as_done(todos: &mut Vec<Todo>, todo_id: u32) {
    for todo in todos {
        if todo.id == todo_id {
            todo.done = true
            return
        }
    }
}

fn todo_titles(todos: &mut Vec<Todo>, todo_id: u32) -> Vec<String> {
    todos.iter()
        .map(|todo| todo.title)
        .collect()
}
```

But this is only `v0.0.1`, we really want this to be *the* ToDo app, so let's fast-forward 3 years and scope creep the hell out of this object:

```rust
struct Todo {
    id: u32,
    text: String,
    done: bool,
    finished_at: Option<DateTime>,
    due_date: Option<OffsetDateTime>,
    priority: u8,
    created_by: String,
    assigned_to: String,
    depends_on: Vec<u32>,
    /// And so on..
}
```
Our API is now thoroughly broken. All these new fields need to be instantiated, `mark_as_done` doesn't set the `finished_at` field, and `todo_titles` doesn't respect `priority` _nor_ `due_date`!



## Kubernetes



## Archetypes
