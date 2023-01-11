+++
title = "Errable - The Lost Sibling of Result and Option"
date = 2023-01-11
draft = false
[taxonomies]
tags = ["rust", "error handling", "errable"]
+++

<a href="https://crates.io/crates/errable" style="box-shadow: none">
    <img src="https://img.shields.io/crates/v/errable" style="display: inline;" />
</a>

<a href="https://docs.rs/errable/latest/errable/" style="box-shadow: none">
    <img src="https://docs.rs/errable/badge.svg" style="display: inline;" />
</a>

<a href="https://github.com/MathiasPius/errable" style="box-shadow: none">
    <img src="https://img.shields.io/badge/GitHub-errable-blue" style="display: inline;" />
</a>

If you're familiar with Rust, then [Result](https://doc.rust-lang.org/std/result/enum.Result.html)
and [Option](https://doc.rust-lang.org/std/option/enum.Option.html) are probably second nature to you,
and they're amazing tools! Sum-types enable performant error handling, and language attributes like
[`#[must_use]`](https://rust-lang.github.io/rfcs/1940-must-use-functions.html) ensures errors are not left unaddressed.

But you will also almost certainly have encountered or written a function which could produces either
an error *or* side-effects, with no actual return value in the successful case.

A great example of this is the [`std::fmt::Display`](https://doc.rust-lang.org/std/fmt/trait.Display.html) trait. 
Implementing this trait requires you to fulfill the following contract:
```rust
fn fmt(&self, f: &mut Formatter<'_>) -> Result<(), Error>;
```
But what's with the `Result<(), Error>`? Obviously the function can fail, so the `Error` makes sense, but why is the Rust standard library using a `Result` for a function which clearly produces no output value? The description for `Result` even says that:

> It is an enum with the variants, Ok(T), representing success **and containing a value**, and Err(E) (...)

Yet our result contains no value! A better definition might use `Option<Error>` instead, which clearly conveys that this function *may* produce an error, but that forces you to give up the incredibly powerful and ergonomic `?` (or [`Try`](https://doc.rust-lang.org/std/ops/trait.Try.html)) syntax:

```rust
fn might_fail() -> Option<Error> { /* ... */ }

fn do_thing() -> Option<OtherError> {
    // Causes do_thing to return None, if might_fail() succeeds,
    // this is the *opposite* of what we want!
    might_fail()?;
    
    // Instead you'll have to do the following to propagate
    // the error, but if you find this appealing, you'd 
    // probably be much happier writing Go ;)
    if let Some(err) = might_fail() {
        return Some(err.into());
    }

    None
}
```
Clearly `Option` is a dead end, but `Result` is still misleading!

What we *really* want is the intention of `Option` with the `Try`-semantics of `Result`!

## Introducing Errable
[Errable](https://docs.rs/errable/latest/errable/) is to quote the crate documentation:
> an Option with inverted Try-semantics.

It fills the gap left by `Option` and `Result` by providing a type that signifies either the successful completion of an operation *or* an error.

<table style="width: 200px; margin-left: auto; margin-right: auto; text-align: center">
    <thead>
        <tr>
            <th>Success</th>
            <th>Failure</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>Result&lt;T</td>
            <td>E&gt;</td>
        </tr>
        <tr>
            <td>Option&lt;T&gt;</td>
            <td><b>Errable&lt;E&gt;</b></td>
        </tr>
    </tbody>
</table>

This means that we can rewrite our example above as succinctly as:
```rust
fn might_fail() -> Errable<Error> { /* ... */ }

fn do_thing() -> Errable<OtherError> {
    might_fail()?;
    might_fail()?;
    might_fail()?;
    
    Success
}
```
And that's it, the best of both worlds!

More practical and in-depth information about how to use this library can be found in the [docs](https://docs.rs/errable/latest/errable/)

---
Feedback and comments are extremely welcome on the GitHub [issues](https://github.com/MathiasPius/errable/issues) page for the [project](https://github.com/MathiasPius/errable). It wouldn't be first time I dedicated hours of my life to fulfilling a niche, only to find out
afterwards that the problem I was solving didn't exist, and by the way my solution doesn't *actually* solve it, so please shoot this down!

## So why isn't this in the standard library/not already a thing?
I don't know. And I'm definitely not saying it should be!

It's incredible hard to google why something *doesn't* exist and it was pretty hard to explain why I didn't just use `Result<(), E>` like literally everybody else.

That being said, I can think of a couple of decent reasons off the top of my head:

1. The use case is adequately covered by `Result<(), E>`.

    This is the most obvious one, evidently it works, since the entire standard library is riddled with it, and nobody is rioting in the streets.

    If I were to be a little provocative, I would perhaps ask why `Option` exists, when its use cases could just as easily be covered by `Result<T, ()>`.

2. Rust's standard library is not intended to be all-encompassing.

    The Rust core language makes a point of *not* being an "everything and the kitchen sink" language, which is part of what makes it so agile.

    By delegating implementation of features that might be considered "standard" in other languages, Rust is able to iterate
    and improve, without introducing major breaking changes to core language features, such as the ongoing evolution of error handling crates
    over the years, or the multiple competing asynchronous runtimes.

3. It adds even more ways of doing the same thing.

    I really like this point. I'm a huge fan of having just one way of doing things, and this no doubt adds complexity by simply existing,
    but I would argue that clearly communicating intent when designing the signatures of your functions is an absolute readability win.

I think it comes down to the 80/20 rule, or perhaps more like 95/5 rule in this case. 95% of use cases can be covered by Result and Option,
and introducing 500+ lines of code to cover the 5% case, and then forcing it down the Rust population's collective throats is wildly disproportionate.

It's been said that perfection is achieved when there's nothing left to take away, and that feckin' `()` needs to *go*!