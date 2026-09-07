import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_generator3/src/string_case.dart';
import 'package:graphql_generator3/src/type_checkers.dart';
import 'package:source_gen/source_gen.dart';

/// Returns true if [t] is an enum type.
bool isTypeEnum(DartType t) => t is InterfaceType && t.element is EnumElement;

/// Returns true if [t] is an iterable type (e.g. List, Set).
bool isTypeIterable(DartType t) =>
    t is InterfaceType && iterableTypeChecker.isAssignableFromType(t);

/// Returns true if [t] is exactly the Dart `Object` type.
bool isTypeObject(DartType t) =>
    t is InterfaceType && objectTypeChecker.isExactlyType(t);

/// Returns true if [t] is exactly a `JsonKey` annotation type.
bool isTypeJsonKey(DartType t) =>
    t is InterfaceType && jsonKeyTypeChecker.isExactlyType(t);

/// Returns true if [t] is exactly a `JsonValue` annotation type.
bool isTypeJsonValue(DartType t) =>
    t is InterfaceType && jsonValueTypeChecker.isExactlyType(t);

/// Returns true if [clazz] is an abstract class.
/// Used to detect GraphQL interfaces.
bool isTypeInterface(ClassElement clazz) => clazz.isAbstract;

/// Returns true if [t] is the same type as [clazz].
bool isSelfType(DartType t, ClassElement clazz) =>
    t is InterfaceType && t.element.displayName == clazz.displayName;

/// Returns true if [t] is either the same type as [clazz]
/// or an iterable of that type.
bool isSelfOrListOfSelf(DartType type, ClassElement clazz) {
  final nonNull = type is InterfaceType
      ? type
      : (type is TypeParameterType ? type.bound as InterfaceType? : null);

  if (nonNull != null && nonNull.element == clazz) {
    return true;
  }

  if (nonNull != null &&
      nonNull.isDartCoreList &&
      nonNull.typeArguments.isNotEmpty &&
      nonNull.typeArguments.first is InterfaceType &&
      (nonNull.typeArguments.first as InterfaceType).element == clazz) {
    return true;
  }

  return false;
}

/// Returns true if [clazz] or one of its superclasses
/// is annotated with @GraphQLClass.
bool isTypeGraphQLClass(InterfaceType clazz) {
  InterfaceType? search = clazz;
  while (search != null) {
    if (classTypeChecker.hasAnnotationOf(search.element)) {
      return true;
    }
    search = search.superclass;
  }
  return false;
}

/// Returns the type argument of an iterable [t], or null if none exists.
DartType? iterableArg(DartType t) =>
    isTypeIterable(t) ? (t as InterfaceType).typeArguments.first : null;

/// Returns the documentation string for [element], either from comments
/// or from a @GraphQLDocumentation annotation.
String? descriptionFor(Element element) {
  var docString = element.documentationComment;
  if (docString == null && graphQLDoc.hasAnnotationOf(element)) {
    final ann = graphQLDoc.firstAnnotationOf(element);
    final cr = ConstantReader(ann);
    docString = cr.peek('description')?.stringValue;
  }
  if (docString == null) return null;
  return docString.replaceAll(docComment, '').replaceAll('\n', '\\n');
}

/// Applies a description from [element] (doc comment or annotation)
/// into [named] under the "description" key.
void applyDescription(Map<String, Expression> named, Element element) {
  String? docString;
  if (graphQLDoc.hasAnnotationOf(element)) {
    final ann = graphQLDoc.firstAnnotationOf(element);
    final cr = ConstantReader(ann);
    docString = cr.peek('description')?.stringValue;
  }

  docString ??= element.documentationComment;

  if (docString != null) {
    named['description'] = literalString(
      docString.replaceAll(docComment, '').replaceAll('\n', '\\n'),
    );
  }
}

/// Computes the GraphQL type name for a class [clazz].
/// - Removes "Bmc" prefix if present.
/// - Adds underscore `_` for outputs.
/// - Adds suffix "Input" for inputs.
String graphQLTypeNameFor(ClassElement clazz, {required bool isInput}) {
  final raw = clazz.displayName; // eg: BmcBddEmployee or BmcBddEmployeeInput

  var base = raw.startsWith('Bmc') ? raw.substring(3) : raw;

  if (isInput) {
    if (base.endsWith('Input')) {
      base = base.substring(0, base.length - 'Input'.length);
    }
    return '_${base}Input';
  }

  return base.startsWith('_') ? base : '_$base';
}

/// Builds the import path for a resolver function based on [clazz] and [fieldName].
String resolverImportFor(
  ClassElement clazz,
  String fieldName, {
  required String packageName,
}) {
  final typeSnake = snakeCase(clazz.displayName); // ex: bmc_device_data
  final fieldSnake = snakeCase(fieldName); // ex: booking_date_data
  return 'package:$packageName/graphql/resolvers/${typeSnake}_${fieldSnake}_resolver.dart';
}

/// Unwraps a `Future<T>` type and returns `T`.
/// If [t] is not a Future, returns [t] as-is.
DartType unwrapFuture(DartType t) {
  if (t is InterfaceType &&
      t.typeArguments.isNotEmpty &&
      t.element.displayName == 'Future') {
    return t.typeArguments.first;
  }
  return t;
}

/// Resolves the GraphQL type expression for a Dart type [dartType],
/// handling async resolution for cross-type references.
/// Uses a cache to avoid duplicate async resolutions.
Future<Expression> graphQLTypeForDartType(
  ClassElement clazz,
  String memberName,
  DartType dartType,
  Resolver resolver, {
  required bool forInput,
  required Map<String, Future<Expression>> cache,
}) async {
  final unwrapped = unwrapFuture(dartType);
  // Check if the type is a GraphQL class and is not the current class
  if (unwrapped is InterfaceType) {
    final typeName = unwrapped.element.displayName;
    final isGraphQLClass = isTypeGraphQLClass(unwrapped);
    if (isGraphQLClass && typeName != clazz.displayName) {
      if (!cache.containsKey(typeName)) {
        // Asynchronously resolve the type of the other class.
        cache[typeName] = inferType(
          clazz.displayName,
          memberName,
          unwrapped,
          forInput,
          resolver,
        );
      }
      return await cache[typeName]!;
    }
  }

  // For other types, use the standard inference logic
  return await inferType(
    clazz.displayName,
    memberName,
    unwrapped,
    forInput,
    resolver,
  );
}

/// Special handling for input fields: allows `self` references
/// and `listOf(self)` for recursive input object types.
Future<Expression> graphQLTypeForInputField(
  ClassElement clazz,
  String memberName,
  DartType dartType,
  Resolver resolver, {
  required Map<String, Future<Expression>> cache,
}) async {
  if (isTypeIterable(dartType)) {
    final arg = iterableArg(dartType);
    if (arg != null && isSelfType(arg, clazz)) {
      var e = refer('listOf').call([refer('self')]);
      if (dartType.nullabilitySuffix == NullabilitySuffix.none) {
        e = e.property('nonNullable').call([]);
      }
      return e;
    }
  }

  if (isSelfType(dartType, clazz)) {
    Expression e = refer('self');
    if (dartType.nullabilitySuffix == NullabilitySuffix.none) {
      e = e.property('nonNullable').call([]);
    }
    return e;
  }

  return await graphQLTypeForDartType(
    clazz,
    memberName,
    dartType,
    resolver,
    forInput: true,
    cache: cache,
  );
}

/// Maps Dart primitive types to GraphQL scalar types.
/// Returns null if the type is not primitive.
Expression? inferPrimitive(DartType type) {
  if (stringTypeChecker.isAssignableFromType(type)) {
    return refer('graphQLString');
  }
  if (intTypeChecker.isAssignableFromType(type)) {
    return refer('graphQLInt');
  }
  if (doubleTypeChecker.isAssignableFromType(type)) {
    return refer('graphQLFloat');
  }
  if (boolTypeChecker.isAssignableFromType(type)) {
    return refer('graphQLBoolean');
  }
  if (dateTimeTypeChecker.isAssignableFromType(type)) {
    return refer('graphQLDate');
  }
  return null;
}

/// Infers the GraphQL type expression for a Dart [type].
/// Supports:
/// - primitives
/// - iterables
/// - enums
/// - classes annotated with @GraphQLClass, @GraphQLInputClass, or @GraphQLUnion.
/// Throws if the type cannot be inferred.
Future<Expression> inferType(
  String className,
  String name,
  DartType type,
  bool isInputType,
  Resolver resolver,
) async {
  // --- Handle primitives first ---
  final primitive = inferPrimitive(type);
  if (primitive != null) {
    return primitive;
  }

  // --- Handle iterables like List<T> ---
  if (isTypeIterable(type)) {
    final arg = iterableArg(type);
    if (arg != null) {
      final inner = await inferType(
        className,
        name,
        arg,
        isInputType,
        resolver,
      );
      return refer('listOf').call([inner]);
    }
  }

  // --- If not an InterfaceType, we can't resolve further ---
  if (type is! InterfaceType) {
    throw 'Cannot infer the GraphQL type for field $className.$name (type=$type).';
  }

  // --- Enums ---
  if (isTypeEnum(type)) {
    return refer('${camelCase(type.element.displayName)}GraphQLType');
  }

  // --- GraphQLClass (output) ---
  if (classTypeChecker.hasAnnotationOf(type.element)) {
    return refer('${camelCase(type.element.displayName)}GraphQLType');
  }

  // --- GraphQLInputClass (input) ---
  if (inputClassTypeChecker.hasAnnotationOf(type.element)) {
    return refer('${camelCase(type.element.displayName)}InputGraphQLType');
  }

  // --- GraphQLUnion ---
  if (unionTypeChecker.hasAnnotationOf(type.element)) {
    if (isInputType) {
      throw 'Union types are not allowed in input fields ($className.$name).';
    }
    return refer('${camelCase(type.element.displayName)}GraphQLType');
  }

  // --- Fallback: unsupported type ---
  throw 'Cannot infer GraphQL type for field $className.$name (type=$type). '
      'Missing @GraphQLClass, @GraphQLInputClass, or @GraphQLUnion annotation.';
}

String? cleanDescription(String? doc) {
  if (doc == null) return null;
  return doc
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^\s*///\s?'), ''))
      .join(' ')
      .trim();
}

List<FieldElement> collectFields(ClassElement clazz) {
  final fields = <FieldElement>[];
  InterfaceType? search = clazz.thisType;

  while (search != null && !isTypeObject(search)) {
    for (final f in search.element.fields) {
      if (f.isStatic || !f.isOriginDeclaration) continue;
      if (fields.any((e) => e.displayName == f.displayName)) continue;
      fields.add(f);
    }
    search = search.superclass;
  }

  return fields;
}
