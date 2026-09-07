import 'package:analyzer/dart/element/element.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_generator3/src/string_case.dart';
import 'package:graphql_generator3/src/type_checkers.dart';
import 'package:source_gen/source_gen.dart';

import 'helpers.dart';

/// Builds a [Library] that defines a `GraphQLEnumType`
/// for a given Dart enum annotated with `@GraphQLClass`.
///
/// This function inspects the [EnumElement] provided (`clazz`) and generates
/// a top-level `final` field representing its GraphQL type. The field:
/// - Is named based on the enum's class name, converted to camelCase and
///   suffixed with `GraphQLType` (e.g., `myEnumGraphQLType`).
/// - Uses `enumTypeFromStrings` to map the enum constants to GraphQL values.
/// - Includes an auto-generated docstring referencing the original Dart enum.
/// - Applies any description provided via doc comments or
///   `@GraphQLDocumentation` annotations.
///
/// Example:
/// ```dart
/// enum MyEnum { foo, bar }
///
/// // Generated:
/// final GraphQLEnumType<String> myEnumGraphQLType =
///   enumTypeFromStrings(
///     'MyEnum',
///     ['foo', 'bar'],
///     description: '...'
///   );
/// ```
///
/// This function is part of the GraphQL schema generator pipeline and ensures
/// that Dart enums can be directly exposed as GraphQL enums.
Library buildEnumSchemaLibrary(EnumElement clazz) {
  return Library((b) {
    final className = clazz.displayName;

    // Everything below is built as code_builder expressions rather than
    // concatenated source. The previous version pasted descriptions straight
    // into a string literal and escaped only the single quote, so a doc comment
    // containing a backslash emitted Dart that no longer said what the comment
    // said - and, often enough, Dart that did not parse.
    final values = clazz.constants.map((f) {
      final named = <String, Expression>{};

      final valueDescription = cleanDescription(f.documentationComment);
      if (valueDescription != null && valueDescription.isNotEmpty) {
        named['description'] = safeLiteralString(valueDescription);
      }

      final depAnn = deprecatedTypeChecker.firstAnnotationOf(f);
      if (depAnn != null) {
        named['deprecationReason'] = safeLiteralString(
          ConstantReader(depAnn).peek('message')?.stringValue ?? 'Deprecated.',
        );
      }

      return refer('GraphQLEnumValue').call([
        literalString(f.displayName),
        refer(className).property(f.displayName),
      ], named);
    }).toList();

    final named = <String, Expression>{};
    final description = cleanDescription(clazz.documentationComment);
    if (description != null && description.isNotEmpty) {
      named['description'] = safeLiteralString(description);
    }

    b.body.add(
      Field((b) {
        b
          ..name = '${camelCase(className)}GraphQLType'
          ..docs.add('/// Auto-generated from [$className].')
          ..type = TypeReference(
            (b) => b
              ..symbol = 'GraphQLEnumType'
              ..types.add(refer(className)),
          )
          ..modifier = FieldModifier.final$
          ..assignment = refer('GraphQLEnumType')
              .call(
                [literalString(className), literalList(values)],
                named,
                [refer(className)],
              )
              .code;
      }),
    );
  });
}
