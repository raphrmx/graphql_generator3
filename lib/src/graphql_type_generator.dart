
import 'package:analyzer/dart/element/element2.dart';
import 'package:angel3_serialize_generator/angel3_serialize_generator.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:source_gen/source_gen.dart';

import 'build_class_schema.dart';
import 'build_enum_schema.dart';

/// A source_gen generator that builds GraphQL schema types
/// for classes and enums annotated with `@GraphQLClass`.
///
/// This generator supports two kinds of annotated elements:
/// - **Classes**: Generates a `GraphQLObjectType` representation
///   with fields mapped from the class’ properties and methods.
/// - **Enums**: Generates a `GraphQLEnumType` based on the enum’s values.
///
/// Example (class):
/// ```dart
/// @GraphQLClass()
/// class Person {
///   final String name;
///   final int age;
/// }
/// ```
///
/// Will generate:
/// ```dart
/// /// Auto-generated from [Person].
/// final GraphQLObjectType personGraphQLType = objectType(
///   '_Person',
///   isInterface: false,
///   fields: [
///     field('name', graphQLString, ...),
///     field('age', graphQLInt, ...),
///   ],
/// );
/// ```
///
/// Example (enum):
/// ```dart
/// @GraphQLClass()
/// enum Status { active, inactive }
/// ```
///
/// Will generate:
/// ```dart
/// /// Auto-generated from [Status].
/// final GraphQLEnumType<String> statusGraphQLType =
///   enumTypeFromStrings('Status', ['active', 'inactive']);
/// ```
class GraphQLGenerator extends GeneratorForAnnotation<GraphQLClass> {
  @override
  Future<String> generateForAnnotatedElement(
      Element2 element,
      ConstantReader annotation,
      BuildStep buildStep,
      ) async {
    // If the annotated element is a class,
    // build a GraphQL object type schema.
    if (element is ClassElement2) {
      final packageName = buildStep.inputId.package;

      // Collect serialization context for the class.
      final ctx = await buildContext(
        element,
        annotation,
        buildStep,
        buildStep.resolver,
        serializableTypeChecker.hasAnnotationOf(element),
      );

      // Build the schema library for the class (output type).
      final lib = await buildClassSchemaLibrary(
        element,
        ctx,
        annotation,
        false, // isInputType = false (this generator only handles output types)
        packageName: packageName,
        resolver: buildStep.resolver,
      );

      return lib.accept(DartEmitter()).toString();
    }

    // If the annotated element is an enum,
    // build a GraphQL enum type schema.
    if (element is EnumElement2) {
      final lib = buildEnumSchemaLibrary(element, annotation);
      return lib.accept(DartEmitter()).toString();
    }

    // Any other element type is unsupported.
    throw UnsupportedError(
      '@GraphQLClass() is only supported on classes or enums.',
    );
  }
}

