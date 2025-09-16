import 'package:build/build.dart';
import 'package:graphql_generator3/src/graphql_input_generator.dart';
import 'package:graphql_generator3/src/graphql_type_generator.dart';
import 'package:graphql_generator3/src/graphql_union_generator.dart';
import 'package:source_gen/source_gen.dart';

Builder graphQLBuilder(_) {
  return SharedPartBuilder([GraphQLGenerator(), GraphQLInputGenerator(), GraphQLUnionGenerator()], 'graphql_generator3');
}
