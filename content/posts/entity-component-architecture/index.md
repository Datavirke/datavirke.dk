+++
title = "Entity Component Architecture"
date = 2023-05-15
draft = false
[taxonomies]
tags = ["ecs", "architecture", "monolith", "microservices"]
+++


Entity-Component-System (ECS) architecture has gained a lot of traction within the games development industry in the past decade, but the ideas that has popularized it in this niche are applicable in many other facets of software development.

One of the primary sources of headaches and tech-debt incursion when writing software is dealing with the inevitable cases where the software's model of the world doesn't match reality. 

* New knowledge of the domain in which it operates is discovered, partially or completely invalidating assumptions made explicitly or implicitly by the product. 

* The business requires rapid expansion into an adjacent domain in a short span of time to take advantage of an opportunity. 

* Customer with outsized share of the revenue demands features unique to their use case.

Whatever the cause, your software has to change, and fast.

---

Knowing that this will inevitably happen on some scale, allows us to make proactive choices to make the change less traumatic, but they bring their own problems:

1. **Exhaustive preemptive mental modeling of the domain.**

    Highly impractical and unlikely to succeed, this approach assumes that the problem space is a completely static and *well known* size. This is the utopia of Waterfall systems design, where with enough information all possible contingencies can be planned for.
    
    Even if we assume that your product is completely green-field, has zero constraints, with the smartest people in the world working on the dullest and most predictable problem possible, your odds of success are not stellar.

2. **Raise the level of encapsulation through microservices.**

    At this point microservices as a cure-all is starting to lose favor in places where organizational coordination at a massive scale is *not* the biggest obstacle to success, and probably for good reason.
    
    Pushing the interface from objects in a monolith to networked services doesn't solve the problem, it just moves the coordination problem up one level. The added rigidity and reduced development velocity might save you from the occasional careless shortcut, but won't help you when the C-levels are breathing down your neck to implement a new feature by weeks end.

## The Third Way

ECS agrees with the premises of the microservice proposal but looks in the opposite direction for a solution.

Instead of raising the level of encapsulation from Object to Service and exacerbating the issue of scoping and slicing in the process, it instead side-steps the whole problem by reducing everything to its most basic components.

Naming things is one of the hardest problems in computer science, especially when the *thing* is half-elephant and half-platypus. By expressing this fantastic animal as simply *4 legs, tusks, and egg-laying* it's very hard to imagine a case where new information or requirements might invalidate that description.

<figure>

![Rendering of a Platyphant, made with https://perchance.org/animal-maker](platyphant.jpg)

<figcaption><small>Platyphant.</small></figcaption>
</figure>

Even if by some miracle the animal was to grow an extra uterus and start spawning live young as well, it won't upset our world, and the incubation-planning-system can just chug along unbothered.

---

Connected only by an `EntityID`, it no longer matters what a canonical "Order" or "Shipment" is, nor which system owns the representation. Stored in a shared database the same Entity can contain a `BasketOf` and both a `PaymentMethod` and `ShippingLocation` component, meaning your *OrderService* and *ShipmentService* can be reduced to simple systems each operating on their own incomplete view of the same entity.

<figure>

![Order Tracking](order-tracking.svg)

<figcaption><small>What an architecture for representing customers, orders, and shipments might look like.</small></figcaption>
</figure>

When your team lead announces that the subset of *Orders* produced by a partnership with another company must be tracked for reimbursement and budget reasons, you just introduce a `PartnerId` component to the order upon referral. This leaves both order and shipping systems, and all the other components besides, completely  untouched.

# Practical Implementation

I've been talking about the nature of an ECS architecture in slightly vague terms, especially *systems*, and hand-waving away details like where data is actually stored. I'll attempt to make up for that by outlining a setup which you should be able to get some mileage out of.

## Storage

Entities being simple IDs and Components generally being very flat objects means that the architecture lends itself to storage within a relational database.

Since entities don't carry any information by themselves, an "Entity" table is not required, but can have uses:

1. **Implementing cascading deletes for owned components.**

    By storing the `EntityID` in a central table and configuring component tables with foreign keys and cascading deletes, you can outright remove an entire entity and all of its components in one fell swoop.

2. **Storing metadata about the entity.**

    For debugging purposes, it might be helpful to know which service originated a specific entity.

3. **Entity-wide locking mechanism.**

    Using the entity table to store ownership information might be handy to indicate that an entity is in a transitionary phase and shouldn't be modified by other systems. In most cases I would argue for
    indicating this kind of state using components. The fact that a virtual machine is restarting should prevent systems from updating software

Each component gets its own table consisting of an `EntityID` and the component's data laid out into separate columns. If the data does not fit into simple columns, it might be that the component could be simplified further.

In the order tracking example from before it might be tempting to store the purchased items as an array of product IDs as a single `OrderItems` component on the order itself, but this effectively cements the nature of an *order item*, preventing other systems from tagging and extending it if necessary. Adding coupon codes, referrals or other promotional metadata to an individual *order item* will require coordination with all other systems which utilizes the `OrderItems` component!

## Systems

A system, broadly defined, is any kind of computation which acts on entities and their components.

If your data is stored in a sqlite database used by your monolithic web-shop, a *system* might be an http request handler responding to a customer's checkout, or it could be an asynchronous function call which performs periodic price adjustment or inventory updates.

In larger architectures you might opt to move your data storage into a separate dedicated SQL database like Postgres, in which case a system could be anything from the aforementioned webshop monolith, to an ad hoc bash script which prunes components containing customer data in compliance with privacy laws.

Storing all the data in a network-accessible SQL database means that systems can be written in anything which speaks SQL. Splitting everything into their component parts allows systems to query exactly the data they're interested in without having to send or discard large amounts of information over the wire, as is common in RESTful APIs.

## Ergonomics

While ECS architectures do away with statically bounded *objects*, it's still really helpful to be able to refer to a collection of components by name, within the limited context of a single system. To an order processing system, `BasketOf` + `ShippingLocation` + `PaymentMethod` *is* an order.

These named collections of components are called *Archetypes*.

## Performance

Sharding

## Security

DB Auth Row-Level Security, Component encryption



# Caveats, Downsides & Pitfalls

* Component Sprawl/Unknown unknowns -> Simplify
* Conflict (naming) -> Be explicit
* Thrashing
* Versioning/Migration -> Simplify and up-front design
* Centralization -> Sharding?

# Addendum

* GraphQL
* Migration
