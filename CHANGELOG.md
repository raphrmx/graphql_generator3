# Change Log

## 3.2.1

### Changed
- `LICENSE` carries a copyright notice for the work done on this line, next to
  the upstream one it has always kept, as the BSD-3-Clause terms require.
  `AUTHORS.md` already recorded who did what; the licence file now says the same
  thing.
- The README says where to look for both, rather than describing the licence
  file as untouched.
- The README links each dependency to its pub.dev page. The pointer between
  these packages went to GitHub, which is the wrong destination from a pub.dev
  page.

No code changed.

## 3.2.0

First release published to pub.dev. `graphql_schema3` is now a hosted dependency
rather than a git one, which is what publishing requires and what lets a
consumer resolve the whole stack from pub.

### Fixed
- Descriptions and deprecation reasons are escaped before they are written into
  the generated source. `code_builder` escapes the quote but leaves the
  backslash and the dollar sign alone, so a doc comment mentioning a Windows
  path emitted `'C:\temp'`, where `\t` is a tab, and one mentioning `$rate`
  emitted a string interpolation that does not compile. Every piece of authored
  text now goes through `safeLiteralString`.
- The enum builder assembles `code_builder` expressions like the rest of the
  generator instead of pasting its type together as source text and escaping
  the single quote by hand.
- One rule decides a description. `@GraphQLDocumentation(description:)` is an
  explicit override and wins over the doc comment everywhere; the schema
  preferred the annotation while the generated header preferred the comment, so
  a class carrying both was described two different ways in the same file.
- The resolved-type cache is keyed on the position as well as the type name. A
  union first resolved as a return value answered for the same union seen later
  as a parameter, where it should have been rejected.

### Added
- A `strip_class_prefixes` builder option. The class name prefix dropped when
  naming a GraphQL type was written into the generator; it belongs to whoever
  names the classes. Left unset it keeps stripping `Bmc`, so nothing changes
  for an existing build; set it to `[]` to strip nothing.
- Tests for the naming rule, the option, and the escaping. 39 in all.

### Removed
- `collectFields`, `resolverImportFor`, `isTypeJsonKey`, `isTypeJsonValue` and
  `jsonValueTypeChecker`: none had a caller. The unused `packageName` parameter
  went with them, along with three locals a nested block re-declared over the
  identical ones already in scope.

### Changed
- An input class no longer runs `inferType` over every field only to discard
  the answer: an input field takes its type from `graphQLTypeForInputField`,
  which is the only one that knows how to tie a recursive input back to itself.

### Note on generated output
Regenerating the 179 models of the consuming project gives byte-identical
output on 161 of the 162 generated files. The one difference is the fix: a doc
comment holding an authored `\n` inside a JSON example used to reach the schema
as a real line break, and now reaches it as the two characters the comment
actually spells.

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
