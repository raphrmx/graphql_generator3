# Change Log

## 3.1.0

### Removed
- The `angel3_serialize_generator`, `angel3_serialize` and `angel3_model`
  dependencies, and with them `belatuk_code_buffer` and `charcode`. `angel3_model`
  was never imported. Of `angel3_serialize_generator` the generator used four
  symbols: `dateTimeTypeChecker`, already shadowed by a local one and hidden from
  both imports; `serializableTypeChecker`, whose five call sites tested for an
  `@serializable` annotation no model carries, so every branch was dead; and
  `BuildContext` / `buildContext`, replaced by `GraphQLBuildContext`. That last
  one only ever answered two questions, the name of the generated variable and
  the JSON key of a field, and its `resolveFieldName` was a no-op here because
  `autoSnakeCaseNames` was always `false`. The point was never the six packages:
  it was that `angel3` dictated which `analyzer` this package could use, which is
  what held it seven majors back for months.
- The `recase` dependency. `camelCase` and `snakeCase` were the only conversions
  used; they now live in `lib/src/string_case.dart` with the same word-splitting
  rules, so the generated names are unchanged.
- The `build_config` and `collection` dependencies, neither of which was imported.
- `lib/src/extensions.dart`. It papered over the `Element` / `Element2` split and
  the current analyzer covers all of it, `EnumElement.constants` included.
- The `angel3_serialize.g.part` entry in `required_inputs`. Consumers no longer
  run the `angel3_serialize` builders at all, which drops two phases from their
  build.
- The naming rule inherited from `angel3`, which stripped a leading `_` or a
  leading/trailing `entity` from the class name before deriving the variable name.
  A leading `_` is dropped anyway by the word splitting; a class named `FooEntity`
  now yields `fooEntityGraphQLType` rather than `fooGraphQLType`.

### Changed
- `analyzer` 7 to 14, `source_gen` 3 to 4, `build` 3 to 4 and `build_runner` 2.7
  to 2.16. Migrated to the current element model: no more `Element2` / `element3`
  / `fields2`, and `isSynthetic` on a field is now `!isOriginDeclaration`.
- The SDK floor moves from 3.8 to 3.11, which is what `analyzer` 14 requires.
  This package is a dev dependency, so the floor does not reach an app.
- A doc comment on a **field** or a **method** now becomes its GraphQL
  `description`. It always should have: `applyDescription` is called for every
  field. The compatibility layer around `Element2` answered `null` for anything
  but a class, so those descriptions were silently dropped. Class descriptions
  are unaffected. Nothing else about the generated schema changes: field names,
  types, nullability, resolvers and enum values are byte for byte what they were.

### Added
- A test suite: 32 tests over the builder and the case conversions. There was
  none. The builder tests stub the two annotation libraries by URL, so they need
  neither `graphql_schema3` from git nor a network.
- A CI workflow running format, analyze and test on the stable and beta SDKs.

## 3.0.1

- Fixed the type resolvers, and carried `description` and `@Deprecated` over onto
  enum values.

## 3.0.0

- Initial release
