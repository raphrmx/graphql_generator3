import 'package:build/build.dart';
import 'package:graphql_generator3/src/graphql_input_generator.dart';
import 'package:graphql_generator3/src/helpers.dart';
import 'package:graphql_generator3/src/graphql_type_generator.dart';
import 'package:graphql_generator3/src/graphql_union_generator.dart';
import 'package:source_gen/source_gen.dart';

/// The builder wired up by `build.yaml`.
///
/// Reads one option, `strip_class_prefixes`: the class name prefixes to drop
/// when naming a GraphQL type, so that `BmcBddEmployee` can become `_BddEmployee`
/// without the prefix being written into the generator. Omitted, it keeps the
/// prefix this generator has always stripped; set it to `[]` to strip none.
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       graphql_generator3|graphql:
///         options:
///           strip_class_prefixes: [Bmc]
/// ```
Builder graphQLBuilder(BuilderOptions options) {
  final configured = options.config['strip_class_prefixes'];
  final stripPrefixes = configured is List
      ? configured.map((Object? p) => p.toString()).toList(growable: false)
      : defaultStrippedPrefixes;

  return SharedPartBuilder([
    GraphQLGenerator(stripPrefixes: stripPrefixes),
    GraphQLInputGenerator(stripPrefixes: stripPrefixes),
    GraphQLUnionGenerator(stripPrefixes: stripPrefixes),
  ], 'graphql_generator3');
}
