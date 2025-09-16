import 'package:analyzer/dart/element/element2.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_generator3/src/extensions.dart';
import 'package:graphql_generator3/src/type_checkers.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

import 'helpers.dart';

/// Builds a [Library] that defines a `GraphQLEnumType`
/// for a given Dart enum annotated with `@GraphQLClass`.
///
/// This function inspects the [EnumElement2] provided (`clazz`) and generates
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
Library buildEnumSchemaLibrary(EnumElement2 clazz, ConstantReader ann) {
  return Library((b) {
    final className = clazz.name;

    final desc = cleanDescription(clazz.documentationComment);
    final descArg = desc != null && desc.isNotEmpty
        ? ", description: '${desc.replaceAll("'", "\\'")}'"
        : "";

    final valuesCode = clazz.fields.map((f) {
      if (f.isSynthetic) return null; // ignore "values", etc.
      final v = f.name;

      // description sur chaque valeur
      final vDesc = cleanDescription(f.documentationComment);
      final descPart = (vDesc != null && vDesc.isNotEmpty)
          ? ", description: '${vDesc.replaceAll("'", "\\'")}'"
          : "";

      // deprecated sur chaque valeur
      final depAnn = deprecatedTypeChecker.firstAnnotationOf(f);
      String depPart = "";
      if (depAnn != null) {
        final dep = ConstantReader(depAnn);
        final reason = dep.peek('message')?.stringValue ?? 'Deprecated.';
        depPart = ", deprecationReason: '${reason.replaceAll("'", "\\'")}'";
      }

      return "GraphQLEnumValue('$v', $className.$v$descPart$depPart)";
    }).whereType<String>().join(", ");

    b.body.add(
      Field((b) {
        b
          ..name = '${ReCase(className).camelCase}GraphQLType'
          ..docs.add('/// Auto-generated from [$className].')
          ..type = TypeReference((b) => b
            ..symbol = 'GraphQLEnumType'
            ..types.add(refer(className)))
          ..modifier = FieldModifier.final$
          ..assignment = Code(
            'GraphQLEnumType<$className>('
                '\'$className\', '
                '[$valuesCode]'
                '$descArg'
                ')',
          );
      }),
    );
  });
}
