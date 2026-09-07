# GraphQL Generator 3

[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/graphql_generator3/ci.yml?branch=main&label=build)](https://github.com/raphrmx/graphql_generator3/actions/workflows/ci.yml)
[![Maintainer](https://img.shields.io/badge/Maintainer-Raphael-purple)](https://comapps.be)
[![License](https://img.shields.io/badge/Licence-BSD--3--Clause-blue)](LICENSE)

Generates `package:graphql_schema3` types from annotated Dart classes, for use with
`package:graphql_server3`. Replaces `convertDartType` from `graphql_server3`.

A build-time dependency: it brings `analyzer`, `build`, `source_gen` and
`code_builder`, and nothing of it reaches the running application.

## Usage

Add it as a dev dependency, annotate a class with `@graphQLClass`, and run
`build_runner`.

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
`GraphQLType`, so `BmcBddEmployee` gives `bmcBddEmployeeGraphQLType`. The SDL name
is the class name prefixed with `_`, with a leading `Bmc` dropped, so
`_BddEmployee`.

`@JsonSerializable(fieldRename:)` is deliberately **not** read: honouring it would
rename fields in schemas already serving traffic. Use `@JsonKey(name:)` on the
fields that need it.
