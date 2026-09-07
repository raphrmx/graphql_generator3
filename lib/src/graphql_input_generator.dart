import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_generator3/src/build_context.dart';
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:source_gen/source_gen.dart';

import 'build_class_schema.dart';
import 'helpers.dart';

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
  /// Class name prefixes dropped from the generated type names.
  final List<String> stripPrefixes;

  const GraphQLInputGenerator({this.stripPrefixes = defaultStrippedPrefixes});

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    // Only classes are supported.
    if (element is ClassElement) {
      // Naming context for the class.
      final ctx = GraphQLBuildContext(element);

      // Build the schema library for the input type.
      final lib = await buildClassSchemaLibrary(
        element,
        ctx,
        annotation,
        true, // isInputType = true
        resolver: buildStep.resolver,
        stripPrefixes: stripPrefixes,
      );

      return lib.accept(DartEmitter()).toString();
    }

    // Any non-class annotated element is invalid.
    throw UnsupportedError(
      '@GraphQLInputClass() is only supported on classes.',
    );
  }
}
