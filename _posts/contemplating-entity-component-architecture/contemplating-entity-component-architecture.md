---
title: "Contemplating Entity Component Architecture"
date: 2024-08-31 08:00:00 CEST
tags: ["ecs", "programming", "rust", "correctness", "entity", "component", "system", "oop"]
category: "Software Engineering"
---

Ever since discovering the [Entity Component System](https://en.wikipedia.org/wiki/Entity_component_system) pattern
through [Bevy](https://bevyengine.org/) a few years ago, I've been simultaneously obsessed with it and frustrated
with the lack of attention it is getting outside of the game development world.

Hopefully with this post (which I have been trying to write since at least May of 2023), I'll be able to move the
attention needle just a little bit in the right direction.

## What even is "Entity Component Systems"?

*Entity-Component-Systems* (ECS) is in theoretical terms a way of modelling a problem, the same way one might say
*Object-Oriented Programming* (OOP) is, and since most people are familiar with OOP, comparing the two might be
the easiest way to explain it.

Where OOP models the world as various *Objects* encapsulating properties and behavior, ECS divorces the idea of some
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
that the basic assumptions about a Component are far less likely to change than that of an Object.

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

### Second first day on the Job, again.

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
    //   1. Has a personal name
    //   2. Is a LandianUnionMember
    //   3. Account is marked for closure
    let subjects = store.list<
        PersonalName,
        LandianUnionMember,
        Terminated
    >();

    // the LandianUnionMember and Terminated components are
    // simply ignored, since it is only their presence we care about.
    for (
        entity,
        personal_name,
        _member, 
        _terminated
    ) = subjects {
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

fn tag_celebratemas(
    store: Store
) {
    for (entity, country) in store.list<Country>() {
        if country == "Southland" {
            store.insert(entity, ObservesCelebratemas);
        }
    }
}

fn celebrate_southland_holiday(
    store: Store,
) {
    for (name, email, _celebrates) in store.list<PersonalName, Email, ObservedCelebratemas>() {
        send_celebratory_email(name, email);
    }
}
```

Simple enough. Let's get it reviewed, and compare it to the feedback from last time:

1. ~~Emails to customers whose accounts have been scheduled for deletion, read `Dear <BLANK>, ...`.~~

    ✅ We only send emails to people with a `PersonalName`, but our privacy act implementation deletes this outright, so this does not apply to our ECS implementation.

2. ~~Emails to suppliers start with `Dear <Company Name>, ...`, which isn't very personal at all!~~

    ✅ We don't even use the company name, only `PersonalName` which can be assigned to a *Company* entity during sign up, to address it to our contact within the company

2. The sanctions worked and **Aggressiland** released **Independistan**. which has joined the **Landian Union**.

    Solution: just tag **Independistan** with `LandianUnionMember`.

3. In recognition of kinship with its liberators, **Independistan** also observes *Celebratemas* next week.

    Solution: just tag **Independistan** with `ObservesCelebratemas`.

4. ~~You forgot about the third type of relationship: `Clients`, which are other companies, who purchase from us in bulk.~~

    ✅ No we didn't, we just don't care!

5. Some of our `Employees` also observe *Celebratemas*, and should receive emails as well!

    Solution: Add a checkbox which employees can check and thereby add the `ObservesCelebratemas` marker to their entities.


A lot of our fabricated problems melt away, and the ones that remain are pretty easy to solve. But why?

### 360 No-Scope

In an OOP world, your objects have to be *exhaustive*.

When you set out to design your `Supplier` type, you must engage in dialectic with your entire organization about what `Supplier` means to each department that might interact with your software, and *none* of these departments are going to be in agreement, so you end up with an [all-encompassing](https://en.wikipedia.org/wiki/God_object) `Supplier` class which contains every single aspect of what a supplier *might* be, in order to satisfy everyone.

This Supplier object has now become a binding *contract* with unbounded scope, which your entire organization has to uphold for all eternity. When the domain shifts (and it *will* shift!), you've maximized the effort required to enact change, and every assumption every department ever made about what a Supplier is has to be challenged.

With ECS, you essentially get exactly what Microservices proclaims to give you, but falls short of delivering: Narrow scope and distributed responsibility. When the domain shifts, you don't have to rethink the world from scratch, or bring in representative greybeards with tacit knowledge from every department: The effort of discovering how each component involved is used is necessarily much smaller than that of the entities they represent.

These domain shifts are still going to be painful, but by reducing both the scope of the assumptions that need to be challenged, you've made the work a lot easier for yourself, and those that come after you.

## Archetypes

Passing around whole bag of Components in your code gets a bit tiresome after you've written your third function which acts on a what everyone in your codebase agrees is a *Customer*, but in ECS-world is shaped like a tuple of `(PersonalName, PaymentMethod, ShippingAddress, Membership, Age, EmailAdddress)`.

Instead we can introduce a short-hand for this particular group of components, an archetype or *view* of the entity if you will. This way billing, shipping, and technical support can each have their own `Customer` archetype made up of some subset of components from the same entity, without having to coordinate anything!

```rust
// Shipping
struct Customer {
    personal_name: PersonalName,
    shipping_address: ShippingAddress
}

// Billing
struct Customer {
    personal_name: PersonalName,
    payment_method: PaymentMethod,
    membership: Membership
}

// Technical Support
struct Customer {
    personal_name: PersonalName,
    email_address: Email
}
```

Assembling these archetypes is just a matter of joining the component tables on the entity id and assembling them from each row.

Once again this seems like a complete regression to OOP, but it isn't for the simple reason that Archetypes are secondary derived constructs made up of components, not the other way around! They're simply windows of convenience into an entity, they do not dictate the structure of the underlying entity at all.

## Keeping Score

I hope to at this point have convinced you that the idea at the very least has merit, and if you're itching to apply this pattern in your own project, or just play around with it elsewhere, I don't think you're going to learn much more about it from me, but I would like to just sketch out some of the strengths and weaknesses of this approach that I've discovered while using it.

### Weakness: Fluid Objects

One of the key benefits of ECS is that we don't have to define exactly what an entity *is*, but this comes with a few downsides as well. As a huge fan of [algebraic data types](https://en.wikipedia.org/wiki/Algebraic_data_type) as implemented in Rust for example, I really appreciate being able to use pattern matching to know *exactly* what kind of object I'm dealing with, and to get hit with compiler errors when a new variant is introduced. With the ECS approach, emergent behavior becomes possible, for better or [worse](https://www.bay12games.com/dwarves/mantisbt/view.php?id=9195).

What this means in practice is that you need to be very precise when designing your components. Imagine you work for a Winery where you decide to delete customers younger than 18 by targeting all entities with the components `Name` and `Age`, you might inadverdently be mangling half your inventory because the stock-keeping department decided to use `Age` for a slightly different purpose.

I would still argue that this is *better* than OOP, since the boundaries of what needs to be agreed upon are that much smaller, but it is a potential foot-gun.

One way to guard against this is to either store data which absolutely does not belong to the same domain (inventory and people for example) in separate data-stores entirely, or the simpler option which allows some interoperability in the future (personalized bottles?): adding *Markers* to differentiate between entities.

The latter solution might sound like a regressing to an OOP-worldview, but the difference here is that these markers are composable. An entity could simultaneously be `ECommerceCustomer` and an `Employee`, without causing a schism.

### Strength: Table Storage

ECS lends itself extremely well to the good old-fashioned way of storing data: tables.

Components should generally be kept small, so as to minimize the contract it implies and usually only contains a handful of properties, so storing your components in whatever database software you prefer is pretty easy.

The following components:

```rust
struct Todo {
    thing: String,
}

struct DueDate {
    datetime: DateTime,
}

struct Completion {
    done_by: Entity,
    completed_at: DateTime,
}

struct Name {
    display_name: String,
}
```

Maps easily to SQL:

```sql
create table todos(
    entity uuid primary key,
    thing text not null,
);

create table due_dates(
    entity uuid primary key,
    due_date datetime not null,
);

create table completions(
    entity uuid primary key,
    done_by uuid not null,
    completed_at datetime not null,
)

create table names(
    entity uuid primary key,
    display_name text not null,
);
```
<small>The lack of foreign keys is intentional, since it encodes assumptions about the components themselves and how they might be used. You could perhaps reasonably create a foreign key constraint between the `entity` field of `due_dates` and `todos` since obviously the former require the latter, but by doing so you are also preventing others from re-using your `DueDate` component for other purposes in the future!</small>

With this we can represent our todo app using "Items" made up of `Todo` components and optionally `DueDate`. Upon completion the `Completion` components is simply added.

Our `Done` component contains references to another entity which is (probably) a user with a `Name` component, but could theoretically also be an automated task which marks tasks with expired due dates as `Done`.

It might look like we've just re-invented [database normalization](https://en.wikipedia.org/wiki/Database_normalization), but ECS is a lot more than just the structure of data, it's a method of separating *Objects* into their constituent parts.

A derivative win for this, is that [Object-relational mapping](https://en.wikipedia.org/wiki/Object%E2%80%93relational_mapping), or *ERM* I suppose, actually stops being something you have to fight into submission. ORMs typically break down when you have to attempt to express complex relations between objects, and then effortlessly map that into a multi-layered nested Object structures so your API can express it in JSON terms, only for your client or frontend to throw away 80% of the information. Of course you could implement your API using GraphQL and hundredfold the complexity of both your frontend and backend, or you can simply expose an API endpoint where your frontend or clients can simply choose which components they actually need at that particular time.

Of course this segues us neatly into our next weakness:

### Weakness: Many to Many

When going beyond the examples I've shown above, a few cracks appear. Usually ECS architecture is designed around the idea that each (entity, component) pair is unique. Your entity cannot have multiple `Name` or `DueDate` components associated with it. Most of the time this makes sense since multiple of either of these would be pretty ambiguous, but in some cases this is perfectly reasonable.

It is for example not at all unreasonable to have multiple `ContactEmail` components associated with a company!

One way of resolving this, is to introduce a relational component, like `IsCompanyContactFor`:

```rust
IsCompanyContact { 
    // This would point back at the *Company* entity
    company: Entity 
}
```

This could then be attached to *Employee* entities which all have a singular `ContactEmail` component, linking the two together. Finding the contact for a company is now only a *slightly* more involved process:
```sql
select
    contact_emails.email
from
    contact_emails
join
    is_company_contact
on
    is_company_contact.entity = contact_emails.entity
where 
    is_company_contact.company = $company_entity_id
```

But this query is not complicated and easy to express in most ORMs.

Another way of going about this, is to have the component itself be multi-dimensional:

```rust
struct ContactEmails(
    List<String>,
)
```

As long as your system of record supports it, this doesn't violate the principles of ECS in any way. I would caution against storing *large* amounts of data in this fashion.

The problem is exacerbated by Many-to-Many relationships. These relationships are hard to express succinctly in any format, and in ECS they require a third entity to express, just as they would in SQL.

Building on our above example, we could theorize that a person might be the contact for multiple companies, necessitating an external mapping:

```rust
struct CompanyContact {
    contact: Entity,
    company: Entity
}
```

These `CompanyContact` components would belong to entirely separate entities, most likely never containing any other components and existing merely as "glue" entities.

### Strength: Extensibility

Going off on a bit of a tangent, I'd like to talk about Kubernetes.

I'm a big fan of Kubernetes, and especially it's extensible API-model and Controller/Operator patterns. One thing I *don't* like about Kubernetes, is having to sprinkle annotations all over the place in order to get things to interoperate properly.

As a brief introduction, Kubernetes models the world internally as *Objects*: Services, Pods, Deployments and so on are all Objects with a strict schema. Here's a `Pod` object as an example:

```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: my-website
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - name: http
      containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations: # Here's your API, good luck!
    some-key: some-value
spec:
  selector:
    app.kubernetes.io/name: my-website
  ports:
    - protocol: TCP
      port: 80
      targetPort: http
```

The problem with this approach is that these objects are very much not extensible, except through this untyped metadata field known as *Annotations*.

Annotations are simple key-value fields which can contain arbitrary (string) data, and is used by developers and Controllers (*systems*) to communicate with each other.

For example, you might configure an [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) object (which is used to route traffic from outside the cluster) with an annotation telling the [Certificate Manager](https://cert-manager.io/) to procure som Let's Encrypt certificates matching the hostname for the ingress:

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    cert-manager.io/issuer: "letsencrypt"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

As a Kubernetes administrator you get used to this type of thing, but it's such an ugly *hack*. These fields are not at all validated, and stringly typed, and if you misspell the key or value, whatever you're trying to accomplish just won't work and you'll need to troubleshoot it somehow.

But it didn't have to be this way! Annotations were never meant to be critical to the functioning of cluster resources, they're just *metadata*. Nonetheless this approach is everywhere in Kubernetes today, simply because it is the easiest way of augmenting existing resources.

If Kubernetes instead was built in an Entity-Component fashion, you could have represented these things in a *much* more extensible way!

Instead of Pods and Containers, you could simply have `Pod` entities defining a context in which to run containers. Containers would exist as independent entities with `Image`, `SecurityContext` and `RunInPod` components pointing to a pod.

When you want to expose a port from one of your containers, you could just attach an `Endpoint` component to your pods *or* containers and model each exposed port as its own entity (with reference to the *Container* entity), allowing `HttpRoutes` and `Certificate` components to be assigned to each of them directly.

And why stop there? Instead of having distinct `DaemonSet`, `StatefulSet` and `Deployment` objects, wherein you duplicate the entire specification for a Pod, you could just create distinct deployment strategy components for each use case, or even express the statefulness of your deployment as yet another component, instead of having to build this information directly into your object definition.

## Conclusion

In conclusion, modelling the world using the Entity Component System pattern removes a ton of pain-points I've encountered while writing code:

1. Endless philosophical discussions about the exact contract of each Object.
2. Mapping runtime objects to persistent data storage, and writing fragile migrations when they change.
3. Lack of flexibility in APIs for picking and choosing data without opening the can of worms that is GraphQL, or writing thousands of lines of boilerplate to cover all permutations.
4. Duplication of functionality and ambiguous source-of-truth when dealing with objects that are ostensibly just different aspects of the same "thing", like for example Orders/Invoice/Payment/Receipt.

This article took a long time to write and I'm extremely curious to hear any and all feedback, especially if you've applied the pattern outside of games develeopment for better or worse!
