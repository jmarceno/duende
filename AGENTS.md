**ALWAYS UPDATE `docs` when making changes to the language that affect its user facing behavior.**
**DO NOT UPDATE THIS FILE IT IS NOT DOCUMENTATION**

# Duende

Compiler for the Duende language, written in D. It transpiles `.du` source to D and builds a native binary with `dmd` (default) or `ldc`.

## What it is and why it was created
Duende is a modern programming language with a focus on being fun to use. Made to feel like a scripting language, but with the assurances of static typing and speed of native binaries. Duende is automatically transpiled to D and compiled with your favorite D compiler.

It was born from my desire to have something that felt like a scripting language, but with some of the guard-rails of static types and the speed of native compilation.

The language just tries to stay out of your way to allow you to do things, you will not find any "purity" here, OOP, Functional...if something is useful we borrow it. This means that no decisions here were taken with some grand theoretical justification, don't overthink why something is the way it is, it just is because I found it to be useful and/or fun, that's it.

## Layout

- `source/` — lexer, parser, semantics, and D codegen
- `examples/` — programs that define language behavior
- `tests/` — pytest that drives those programs through the compiler
- `duende_packages/` — standard library
- `docs/` — language docs

## Tests

Run `./test.sh`. It builds with `dmd`, then runs `uv run pytest -v -n 1`. Requires `dmd`, `dub`, and `uv`.

A test compiles this compiler, compiles a Duende program, runs the binary, and checks its output. New behavior goes in `examples/` with an assertion in `tests/`.

When a program must be rejected, the check is the compiler diagnostic from that compile.

**Unit tests are forbidden, the only tests are end-to-end program assertions.**

## Changes

Keep edits small and aimed at a program that compiles and runs correctly. Language choices stay practical: use what is useful.
