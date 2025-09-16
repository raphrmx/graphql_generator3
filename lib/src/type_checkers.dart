import 'package:source_gen/source_gen.dart';

/// Matches Dart documentation comments starting with `///`.
final docComment = RegExp(r'^/// ', multiLine: true);

/// TypeChecker for the `@GraphQLDocumentation` annotation.
/// Used to extract descriptions or metadata for GraphQL schema elements.
const graphQLDoc = TypeChecker.fromUrl(
  'package:graphql_schema3/src/schema.dart#GraphQLDocumentation',
);

/// TypeChecker for the `@GraphQLClass` annotation.
/// Marks a class as a GraphQL output type.
const classTypeChecker = TypeChecker.fromUrl(
  'package:graphql_schema3/src/schema.dart#GraphQLClass',
);

/// TypeChecker for the `@GraphQLInputClass` annotation.
/// Marks a class as a GraphQL input type.
const inputClassTypeChecker = TypeChecker.fromUrl(
  'package:graphql_schema3/src/schema.dart#GraphQLInputClass',
);

/// TypeChecker for the `@GraphQLResolver` annotation.
/// Identifies methods that should be exposed as GraphQL resolvers.
const resolverTypeChecker = TypeChecker.fromUrl(
  'package:graphql_schema3/src/schema.dart#GraphQLResolver',
);

/// TypeChecker for the `@GraphQLUnion` annotation.
/// Marks a class as a GraphQL union type.
const unionTypeChecker = TypeChecker.fromUrl(
  'package:graphql_schema3/src/schema.dart#GraphQLUnion',
);

/// TypeChecker for the `@JsonKey` annotation.
/// Used to customize JSON field names and serialization behavior.
const jsonKeyTypeChecker = TypeChecker.fromUrl(
  'package:json_annotation/src/json_key.dart#JsonKey',
);

/// TypeChecker for the `@JsonValue` annotation.
/// Used to assign explicit values to enum members in JSON.
const jsonValueTypeChecker = TypeChecker.fromUrl(
  'package:json_annotation/src/json_value.dart#JsonValue',
);

/// TypeChecker for the Dart core `Iterable` type.
const iterableTypeChecker = TypeChecker.fromUrl('dart:core#Iterable');

/// TypeChecker for the Dart core `Deprecated` annotation.
const deprecatedTypeChecker = TypeChecker.fromUrl('dart:core#Deprecated');

/// TypeChecker for the Dart core `Object` type.
const objectTypeChecker = TypeChecker.fromUrl('dart:core#Object');

/// TypeChecker for the Dart core `DateTime` type.
const dateTimeTypeChecker = TypeChecker.fromUrl('dart:core#DateTime');

/// TypeChecker for the Dart core `String` type.
const stringTypeChecker = TypeChecker.fromUrl('dart:core#String');

/// TypeChecker for the Dart core `int` type.
const intTypeChecker = TypeChecker.fromUrl('dart:core#int');

/// TypeChecker for the Dart core `double` type.
const doubleTypeChecker = TypeChecker.fromUrl('dart:core#double');

/// TypeChecker for the Dart core `bool` type.
const boolTypeChecker = TypeChecker.fromUrl('dart:core#bool');
