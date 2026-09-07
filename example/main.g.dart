// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'main.dart';

// **************************************************************************
// GraphQLGenerator
// **************************************************************************

/// Auto-generated from [TodoItem].
final GraphQLObjectType todoItemGraphQLType = objectType(
  '_TodoItem',
  isInterface: false,
  interfaces: [],
  fields: [
    field(
      'text',
      graphQLString,
      resolve: (serialized, args) => (serialized is Map<String, dynamic>)
          ? serialized['text']
          : (serialized as TodoItem).text,
    ),
    field(
      'isComplete',
      graphQLBoolean,
      description: 'Whether this item is complete.',
      resolve: (serialized, args) => (serialized is Map<String, dynamic>)
          ? serialized['isComplete']
          : (serialized as TodoItem).isComplete,
    ),
  ],
);
