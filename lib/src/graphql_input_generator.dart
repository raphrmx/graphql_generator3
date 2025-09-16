
import 'package:analyzer/dart/element/element2.dart';
import 'package:angel3_serialize_generator/angel3_serialize_generator.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:source_gen/source_gen.dart';

import 'build_class_schema.dart';

/// A source_gen generator that builds GraphQL **input object types**
/// for classes annotated with `@GraphQLInputClass`.
///
/// This generator maps Dart class properties into
/// `GraphQLInputObjectType` fields, making them usable
/// as input types in GraphQL queries and mutations.
///
/// Example:
/// ```dart
/// @GraphQLInputClass()
/// class ProductInput {
///   final String name;
///   final double price;
/// }
/// ```
///
/// Will generate:
/// ```dart
/// /// Auto-generated from [ProductInput].
/// final GraphQLInputObjectType productInputGraphQLType = inputObjectType(
///   '_ProductInput',
///   inputFields: [
///     GraphQLInputObjectField('name', graphQLString, ...),
///     GraphQLInputObjectField('price', graphQLFloat, ...),
///   ],
/// );
/// ```
class GraphQLInputGenerator extends GeneratorForAnnotation<GraphQLInputClass> {
  @override
  Future<String> generateForAnnotatedElement(
      Element2 element,
      ConstantReader annotation,
      BuildStep buildStep,
      ) async {
    // Only classes are supported.
    if (element is ClassElement2) {
      final packageName = buildStep.inputId.package;

      // Collect serialization/build context for the class.
      final ctx = await buildContext(
        element,
        annotation,
        buildStep,
        buildStep.resolver,
        serializableTypeChecker.hasAnnotationOf(element),
      );

      // Build the schema library for the input type.
      final lib = await buildClassSchemaLibrary(
        element,
        ctx,
        annotation,
        true, // isInputType = true
        packageName: packageName,
        resolver: buildStep.resolver,
      );

      return lib.accept(DartEmitter()).toString();
    }

    // Any non-class annotated element is invalid.
    throw UnsupportedError(
      '@GraphQLInputClass() is only supported on classes.',
    );
  }
}

