+++
title = "Typesafe Uuids for Rust"
date = 2023-01-15
draft = false
[taxonomies]
tags = ["rust", "typesafe", "uuid"]
+++

<a href="https://crates.io/crates/typed-uuid" style="box-shadow: none">
    <img src="https://img.shields.io/crates/v/typed-uuid" style="display: inline;" />
</a>

<a href="https://docs.rs/typed-uuid/latest/typed_uuid" style="box-shadow: none">
    <img src="https://docs.rs/typed-uuid/badge.svg" style="display: inline;" />
</a>

<a href="https://github.com/MathiasPius/typed-uuid" style="box-shadow: none">
    <img src="https://img.shields.io/badge/GitHub-typed--uuid-blue" style="display: inline;" />
</a>

The [`uuid`](https://crates.io/crates/uuid) crate is a great example of taking a well-defined narrowly scoped design
like those of unique identifiers and creating a well-crafted crate that does *just* enough to be useful, without all the bloat.

I use it a lot in my projects, but I've hit a few scenarios where readability and ease-of-use of my APIs have suffered,
simply from the fact that a function had to deal with multiple `Uuid` at once, and how easy it is to mix them up.

Being a big fan of the [New Type Idiom](https://doc.rust-lang.org/rust-by-example/generics/new_types.html) means the obvious
solution to this problem, is to create a so-called "newtype". That is, wrapping the `Uuid` type in a struct and passing that around instead:

```rust
struct UserId(Uuid);
```
Now you can't use `Uuid` and `UserId` interchangeably, and you're being explicit about what *kind* of Uuid you're passing around.

This solves the problem, and with a few implementations and derives you've practically got all the usability of
a `Uuid`, as well as the type-safety expected of a good API.

... But if you're writing an application past a certain scale, implementing and re-implementing `Deref`, `AsRef`, and so on,
for every single uniquely identifiable object in your domain becomes a bit of a chore, and if it wasn't for the relative simplicity
of those trait implementations, probably an error-prone one too.

This is where [typed-uuids](https://crates.io/crates/typed-uuid) come in.

`typed_uuid::Id<T>` is a generic wrapper around the `Uuid`-type with all the bells and whistles of the newtype solution, but without the code duplication. It allows you to differentiate unique identifiers for different types, letting the compiler keep track of it for you.

```rust
// Define an alias for a v4 unique id for Users
type UserId = Id<User, V4>;

struct User {
    id: UserId,
    name: String,
}
```

`Id<User>` has the exact same properties as a regular `Uuid`. You can serialize and deserialize it, you can print and compare it (to other `Id<User>`), but crucially you cannot compare or convert it to other `Id`s! `UserId` being an *alias* and not a new type, means you don't have to re-implement all the functionality or traits of `Uuid`.

---

Say for example you're writing a blog application, and you're dealing with at least the following different types of uniquely identifiable resources:

```rust
struct User {
    id: Uuid,
    /* ... */
}

struct Article {
    id: Uuid,
    author: Uuid,
    /* ... */
}

struct Comment { 
    id: Uuid,
    article: Uuid,
    author: Uuid,
    /* ... */
}

struct Reaction {
    id: Uuid,
    reactor: Uuid,
    comment: Uuid,
    /* ... */
}

// And so on...
```

Keeping track of all those Uuids while defining your API is a bit of a mouthful! What would the signature for the function we use for persisting data to the database even look like?

```rust
fn leave_comment(
    article_id: Uuid,
    user_id: Uuid,
    comment_id: Uuid,
    content: &str, 
    ...
);
```

The odds of correctly entering all those Uuids in the right order are astronomical! Let's sprinkle some type-safety on there:

```rust
// All our Ids use v4 Uuids, so use this short-hand for simplicity.
type Id<T> = typed_uuid::Id<T, typed_uuid::V4>;

struct User {
    id: Id<User>,
    /* ... */
}

struct Article {
    id: Id<Article>,
    author: Id<User>,
    /* ... */
}

struct Comment { 
    id: Id<Comment>,
    article: Id<Article>,
    author: Id<User>,
    /* ... */
}

struct Reaction {
    id: Id<Reaction>,
    reactor: Id<User>,
    comment: Id<Comment>,
    /* ... */
}
```

Likewise we change the function signature of our database persistence functions:
```rust
fn leave_comment(
    article_id: Id<Article>,
    user_id: Id<User>,
    comment_id: Id<Comment>,
    content: &str,
    ...
);
```

Now it's *really* difficult to mess up our function calls, but let's try it anyway:

```rust
fn comment_handler(db: DB, user: Session<Uuid>, form: Form<PostComment>) {
    let user_id = Id::<User>::from_generic_uuid(*user);

    let article_id = Id::<Article>::from_generic_uuid(form.article_id);

    let comment_id = Id::<Comment>::new();

    // "Accidentally" flip the order of user_id and article_id
    db.leave_comment(
        user_id,
        article_id,
        comment_id,
        form.comment_content
    );
}
```

Compiler saves what would have been just another generic Uuid committed to the database without a second thought:

```
| leave_comment( user_id, article_id, comment_id, "comment");
| ^^^^^^^^^^^^^  -------  ---------- expected `Id<User, V4>`, found `Id<Article, V4>`
|                |
|                expected `Id<Article, V4>`, found `Id<User, V4>`
```
I omitted some `typed_uuid::` prefixes to fit the lines within the page, so the compiler error is a bit messier than shown above, but a compiler error nonetheless!

# Caveats

Obviously you can still mess up. There's nothing stopping you from accidentally deriving the `article_id` from the session instead of the post form, but by explicitly defining the type of `Id` you're working with *at the perimeter*, you only have to do it right once, instead of on every single subsequent call you make using that variable.

If you're using a modern web framework like [axum](https://docs.rs/axum/latest/axum/) for example, you can even move the `user_id` derivation from the function call itself into an extractor, reducing the times you have to write correct code down from *once per handler* to just **once**!

The types of errors produced by mixing up `Uuid`s are usually pretty trivial to catch. In our case it would hopefully have been caught by a foreign key constraint on our database. In other use-cases it might manifest as missing content or obviously invalid behavior by the program, but these are all runtime errors, meaning someone has to actually run the code to be discover them. If we can push discovery of this error right into the software engineer's field of view as they're writing the code, all the better!

I'm also not entirely happy about the verbosity of the error messages caused by the flexibility required for the `Id` type to cover all the different versions. I almost always use `v4` anyway, so it is tempting to simply discard the whole `Version` parameter and simplify the interface a bit. In the future I might choose to create an `Idv4` newtype around `Id<T, V4>`, or perhaps default the `Version` parameter to an `Unversioned` struct which disregards the `Uuid` version number when constructing an `Id` from a generic uuid.


