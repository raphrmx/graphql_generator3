import 'package:analyzer/dart/element/element.dart';
import 'package:graphql_generator3/src/string_case.dart';
import 'package:graphql_generator3/src/type_checkers.dart';
import 'package:source_gen/source_gen.dart';

/// Naming context for one annotated class.
///
/// Replaces the `BuildContext` this generator used to borrow from
/// `angel3_serialize_generator`. Only two questions were ever asked of it:
/// how to name the generated top-level variable, and under which JSON key a
/// field is serialized. Both are answered here, the field name from
/// `package:json_annotation` alone.
class GraphQLBuildContext {
  /// The annotated Dart class this context describes.
  final ClassElement clazz;

  const GraphQLBuildContext(this.clazz);

  /// The Dart class name, as written. Used in the generated doc comment.
  String get modelClassName => clazz.displayName;

  /// The camelCase prefix of the generated variable, eg `bmcBddEmployee`
  /// for `bmcBddEmployeeGraphQLType`.
  String get modelVariablePrefix => camelCase(clazz.displayName);

  /// The JSON key [field] is serialized under: its Dart name, overridden by
  /// `@JsonKey(name: ...)` when one is present.
  ///
  /// Note that `@JsonSerializable(fieldRename:)` is deliberately *not* honoured
  /// here: doing so would rename fields in schemas already in production.
  String jsonNameFor(FieldElement field) {
    final ann = jsonKeyTypeChecker.firstAnnotationOf(field);
    if (ann != null) {
      final forced = ConstantReader(ann).peek('name')?.stringValue;
      if (forced != null && forced.isNotEmpty) {
        return forced;
      }
    }
    return field.displayName;
  }
}
