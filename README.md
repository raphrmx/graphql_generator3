# GraphQL Generator 3

[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/graphql_generator3/ci.yml?branch=main&label=build)](https://github.com/raphrmx/graphql_generator3/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/graphql_generator3?color=blue)](https://pub.dev/packages/graphql_generator3)
[![Maintainer](https://img.shields.io/badge/Maintainer-Raphael-purple)](https://comapps.be)
[![License](https://img.shields.io/badge/Licence-BSD--3--Clause-blue)](LICENSE)

Generates `package:graphql_schema3` types from annotated Dart classes, for use with
`package:graphql_server3`. Replaces `convertDartType` from `graphql_server3`.

A build-time dependency: it brings `analyzer`, `build`, `source_gen` and
`code_builder`, and nothing of it reaches the running application.

## Where this comes from

This package is a fork of the GraphQL stack maintained as part of
[Angel3](https://github.com/dukefirehawk/angel), which itself descends from the
`graphql_*` packages Tobe O wrote for Angel. The fork is taken from the `2`
line; the original BSD-3-Clause licence and its copyright notice are kept
verbatim in [LICENSE](LICENSE), and the bulk of the type system, the parser and
the execution algorithm are still that work.

Why fork at all. Two reasons, and only the second one still holds:

- Upstream had stopped moving while the projects depending on it had not.
  Development there has since resumed, but by then the two lines had diverged
  far enough that merging back would cost more than it returns.
- The stack was pinned to `angel3_*`, and `angel3_*` decided which `analyzer`
  and which Dart SDK everything downstream could use. That is what held the
  generator seven `analyzer` majors back for months. Cutting the tie was the
  point of the `3` line.

So: the `3` line does not track upstream and does not merge from it. It is
maintained on its own, with three rules - as few dependencies as possible, no
dependency that dictates the SDK, and no behaviour without a test covering it.

### The `3` is a lineage marker, not a version and not a succession

`graphql_generator2` is not this package's predecessor. It is its sibling, and it is
alive: 7.0.0 as of August 2026, published by dukefirehawk.com, on its own
numbering that long ago stopped matching the `2` in its name. The `3` here says
only which line this fork was taken from.

If you want the upstream package, take
[`graphql_generator2`](https://pub.dev/packages/graphql_generator2). Take this
one for the smaller dependency tree and the fixes listed below. They have not
been offered upstream. The two lines were compared at upstream 7.0.0: every
release it has cut since the fork point raises the Dart SDK floor or the linter,
and its dependency set is unchanged.

## What version 3 changed

A build-time dependency only: `analyzer`, `build`, `source_gen`, `code_builder`,
`json_annotation` and `graphql_schema3`, whose annotations it reads. Nothing of
it reaches the running application.

Removed:

- `angel3_serialize_generator`, `angel3_serialize` and `angel3_model`, and with
  them `belatuk_code_buffer` and `charcode`. Of the generator package, four
  symbols were used: one already shadowed by a local one, one testing for an
  annotation no model carries, so every branch of it was dead, and a
  `BuildContext` that only ever answered two questions - the name of the
  generated variable, and the JSON key of a field. Those two live in
  `GraphQLBuildContext` now. The point was never the six packages: it was that
  `angel3` decided which `analyzer` this generator could use, which held it
  seven majors back for months.
- `recase`, replaced by `lib/src/string_case.dart` with the same word-splitting
  rules, so the generated names are unchanged.
- `collection` and `build_config`, neither of them used.
- Dead code inside the package: five helpers with no caller, an unused
  `packageName` parameter, and three locals a nested block re-declared over the
  identical ones already in scope.

Fixed:

- Descriptions and deprecation reasons are escaped before they are written into
  the generated source. `code_builder` escapes the quote but leaves the
  backslash and the dollar sign alone, so a doc comment mentioning a Windows
  path emitted a tab where the path had a separator, and one mentioning a price
  emitted a string interpolation that does not compile.
- The enum builder assembles `code_builder` expressions like the rest of the
  generator, instead of pasting its type together as source text.
- One rule decides a description. `@GraphQLDocumentation(description:)` is an
  explicit override and wins over the doc comment everywhere; the schema
  preferred the annotation while the generated header preferred the comment.
- The resolved-type cache is keyed on the position as well as the type name, so
  a union first resolved as a return value no longer answers for the same union
  seen later as a parameter, where it should be rejected.
- A doc comment on a field or a method becomes its GraphQL description. The
  compatibility layer this generator used to carry answered `null` for anything
  that was not a class, so field descriptions were silently dropped.

Added:

- `analyzer` 7 to 14, `source_gen` 3 to 4, `build` 3 to 4. The SDK floor moves
  to 3.11, which is what `analyzer` 14 requires.
- A `strip_class_prefixes` builder option. The class name prefix dropped when
  naming a GraphQL type used to be written into the generator; it belongs to
  whoever names the classes.
- 39 tests, where there were none. They stub the annotation libraries by URL,
  so they resolve nothing from git and nothing from the network.

The full list is in [CHANGELOG.md](CHANGELOG.md).

## Installation

`graphql_generator3` is a dev dependency; `graphql_schema3` carries the
annotations and is a real one.

```bash
dart pub add graphql_schema3
dart pub add dev:graphql_generator3 dev:build_runner
```

## Usage

Annotate a class with `@graphQLClass` and run `build_runner`.

```dart
import 'package:graphql_schema3/graphql_schema3.dart';

part 'todo.g.dart';

/// A single entry on the list.
@graphQLClass
class Todo {
  /// What is to be done.
  final String text;

  /// Whether this item is complete.
  final bool isComplete;

  Todo(this.text, this.isComplete);
}
```

generates:

```dart
/// Auto-generated from [Todo].
final GraphQLObjectType todoGraphQLType = objectType(
  '_Todo',
  isInterface: false,
  description: 'A single entry on the list.',
  interfaces: [],
  fields: [
    field(
      'text',
      graphQLString.nonNullable(),
      description: 'What is to be done.',
      resolve: (serialized, args) => (serialized is Map<String, dynamic>)
          ? serialized['text']
          : (serialized as Todo).text,
    ),
    field(
      'isComplete',
      graphQLBoolean.nonNullable(),
      description: 'Whether this item is complete.',
      resolve: (serialized, args) => (serialized is Map<String, dynamic>)
          ? serialized['isComplete']
          : (serialized as Todo).isComplete,
    ),
  ],
);
```

## Annotations

| Annotation | On | Effect |
| --- | --- | --- |
| `@graphQLClass` / `@GraphQLClass()` | class, enum | Generates a `GraphQLObjectType`, or a `GraphQLEnumType` for an enum. An abstract class becomes an interface. |
| `@GraphQLInputClass()` | class | Generates a `GraphQLInputObjectType`. Self-references are supported and emit a closure. |
| `@GraphQLUnion(types: [...])` | class | Generates a `GraphQLUnionType` over the listed types. |
| `@GraphQLResolver()` | method | Exposes the method as a field, routed through `resolverRegistry['Class.method']`. |
| `@GraphQLDocumentation(description:)` | any | Sets the description, over the doc comment. |
| `@GraphQLSkip` / `@graphQLSkip` | field | Keeps the field out of the schema while leaving it live in Dart. |
| `@Deprecated('...')` | field, method, enum value | Sets `deprecationReason`. |
| `@JsonKey(name:)` | field | Sets the JSON key the field is exposed and resolved under. |

Doc comments become descriptions on types, fields, methods and enum values.

## Naming

The generated variable is the class name in camelCase, suffixed with
`GraphQLType`, so `ComappsBddEmployee` gives `ComappsBddEmployeeGraphQLType`. The SDL name
is the class name prefixed with `_`, with a stripped prefix dropped, so
`_BddEmployee`.

Which prefixes are stripped is the builder's `strip_class_prefixes` option. Left
unset it strips `Comapps`, which is what this generator has always done; set it to
`[]` to strip nothing.

```yaml
targets:
  $default:
    builders:
      graphql_generator3|graphql:
        options:
          strip_class_prefixes: [Comapps]
```

`@JsonSerializable(fieldRename:)` is deliberately **not** read: honouring it would
rename fields in schemas already serving traffic. Use `@JsonKey(name:)` on the
fields that need it.
