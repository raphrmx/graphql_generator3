// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'main.dart';

// **************************************************************************
// _GraphQLGenerator
// **************************************************************************

/// Auto-generated from [TodoItem].
final GraphQLObjectType todoItemGraphQLType = objectType(
  'TodoItem',
  isInterface: false,
  interfaces: [],
  fields: [
    field(
      'text',
      graphQLString,
      resolve: (obj, ctx) {
        final v = (obj is Map<String, dynamic>)
            ? (() {
                final m = obj;
                return m['text'];
              })()
            : (() {
                final o = obj;
                return (o as TodoItem).text;
              })();
        return v;
      },
    ),
    field(
      'isComplete',
      graphQLBoolean,
      resolve: (obj, ctx) {
        final v = (obj is Map<String, dynamic>)
            ? (() {
                final m = obj;
                return m['isComplete'];
              })()
            : (() {
                final o = obj;
                return (o as TodoItem).isComplete;
              })();
        return v;
      },
    ),
  ],
);
