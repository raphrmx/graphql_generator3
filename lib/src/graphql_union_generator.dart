
import 'package:analyzer/dart/element/element2.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_generator3/src/extensions.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

import 'helpers.dart';

/// A source_gen generator that builds GraphQL union types
/// for classes annotated with `@GraphQLUnion`.
///
/// This generator scans for all Dart classes that declare
/// the `@GraphQLUnion` annotation and produces a corresponding
/// `GraphQLUnionType` definition. The generated variable
/// can then be used in a GraphQL schema to represent a union.
///
/// Example:
/// ```dart
/// @GraphQLUnion(types: [Dog, Cat])
/// class Animal {}
/// ```
///
/// Will generate:
/// ```dart
/// /// Auto-generated union from @GraphQLUnion on Animal.
/// final GraphQLUnionType animalGraphQLType = GraphQLUnionType(
///   '_Animal',
///   [dogGraphQLType, catGraphQLType],
/// );
/// ```
class GraphQLUnionGenerator extends GeneratorForAnnotation<GraphQLUnion> {
  @override
  Future<String> generateForAnnotatedElement(
      Element2 element,
      ConstantReader annotation,
      BuildStep buildStep,
      ) async {
    // Ensure the annotation is only applied to a class.
    if (element is! ClassElement2) {
      throw UnsupportedError('@GraphQLUnion() is only supported on classes.');
    }

    // Dart name of the annotated class (e.g., `Animal`)
    final unionDartName = element.name;

    // SDL name of the union type (defaults to GraphQL naming convention)
    final sdlName = annotation.peek('name')?.stringValue ??
        graphQLTypeNameFor(element, isInput: false);

    // Extract the list of types provided in `@GraphQLUnion(types: [...])`
    final typeObjs = annotation.peek('types')?.listValue ?? const [];
    final possibleTypeExprs = <Expression>[];

    // For each referenced type, resolve its name and add its corresponding
    // `xxxGraphQLType` variable as a possible type in the union.
    for (final obj in typeObjs) {
      final dt = ConstantReader(obj).typeValue;
      final el = dt.element3;
      if (el is! ClassElement2) {
        continue; // skip invalid entries
      }
      final dartTypeName = el.name;
      final varIdent = '${ReCase(dartTypeName).camelCase}GraphQLType';
      possibleTypeExprs.add(refer(varIdent));
    }

    // Ensure the union has at least one valid class type.
    if (possibleTypeExprs.isEmpty) {
      throw InvalidGenerationSourceError(
        '@GraphQLUnion(types: [...]) on $unionDartName must contain at least one class type.',
        element: element,
      );
    }

    // Name of the generated variable for this union
    final unionVarName = '${ReCase(element.name).camelCase}GraphQLType';

    // Build the output library that declares the union variable
    final lib = Library((b) {
      b.body.add(
        Field((f) {
          f
            ..docs.add(
              '/// Auto-generated union from @$GraphQLUnion on $unionDartName.',
            )
            ..name = unionVarName
            ..type = refer('GraphQLUnionType')
            ..modifier = FieldModifier.final$
            ..assignment = refer('GraphQLUnionType')
                .call([
              literalString(sdlName),
              literalList(possibleTypeExprs),
            ])
                .code;
        }),
      );
    });

    return lib.accept(DartEmitter()).toString();
  }
}

