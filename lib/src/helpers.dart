
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:angel3_serialize_generator/angel3_serialize_generator.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_generator3/src/extensions.dart';
import 'package:graphql_generator3/src/type_checkers.dart' hide dateTimeTypeChecker;
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';
/// Returns true if [t] is an enum type.
bool isTypeEnum(DartType t) => t is InterfaceType && t.element3 is EnumElement2;

/// Returns true if [t] is an iterable type (e.g. List, Set).
bool isTypeIterable(DartType t) => t is InterfaceType && iterableTypeChecker.isAssignableFromType(t);

/// Returns true if [t] is exactly the Dart `Object` type.
bool isTypeObject(DartType t) => t is InterfaceType && objectTypeChecker.isExactlyType(t);

/// Returns true if [t] is exactly a `JsonKey` annotation type.
bool isTypeJsonKey(DartType t) => t is InterfaceType && jsonKeyTypeChecker.isExactlyType(t);

/// Returns true if [t] is exactly a `JsonValue` annotation type.
bool isTypeJsonValue(DartType t) => t is InterfaceType && jsonValueTypeChecker.isExactlyType(t);

/// Returns true if [clazz] is an abstract class but not a serializable class.
/// Used to detect GraphQL interfaces.
bool isTypeInterface(ClassElement2 clazz) => clazz.isAbstract && !serializableTypeChecker.hasAnnotationOf(clazz);

/// Returns true if [t] is the same type as [clazz].
bool isSelfType(DartType t, ClassElement2 clazz) => t is InterfaceType && t.element3.name == clazz.name;

/// Returns true if [t] is either the same type as [clazz]
/// or an iterable of that type.
bool isSelfOrListOfSelf(DartType type, ClassElement2 clazz) {
  final nonNull = type is InterfaceType
      ? type
      : (type is TypeParameterType ? type.bound as InterfaceType? : null);

  if (nonNull != null && nonNull.element3 == clazz) {
    return true;
  }

  if (nonNull != null &&
      nonNull.isDartCoreList &&
      nonNull.typeArguments.isNotEmpty &&
      nonNull.typeArguments.first is InterfaceType &&
      (nonNull.typeArguments.first as InterfaceType).element3 == clazz) {
    return true;
  }

  return false;
}

/// Returns true if [clazz] or one of its superclasses
/// is annotated with @GraphQLClass.
bool isTypeGraphQLClass(InterfaceType clazz) {
  InterfaceType? search = clazz;
  while (search != null) {
    if (classTypeChecker.hasAnnotationOf(search.element3)) {
      return true;
    }
    search = search.superclass;
  }
  return false;
}

/// Returns the type argument of an iterable [t], or null if none exists.
DartType? iterableArg(DartType t) => isTypeIterable(t) ? (t as InterfaceType).typeArguments.first : null;

/// Returns the documentation string for [element], either from comments
/// or from a @GraphQLDocumentation annotation.
String? descriptionFor(Element2 element) {
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
void applyDescription(Map<String, Expression> named, Element2 element) {
  String? docString;
  if (graphQLDoc.hasAnnotationOf(element)) {
    final ann = graphQLDoc.firstAnnotationOf(element);
    final cr = ConstantReader(ann);
    docString = cr.peek('description')?.stringValue;
  }

  docString ??= element.documentationComment;

  if (docString != null) {
    named['description'] = literalString(docString.replaceAll(docComment, '').replaceAll('\n', '\\n'));
  }
}

/// Computes the GraphQL type name for a class [clazz].
/// - Removes "Bmc" prefix if present.
/// - Adds underscore `_` for outputs.
/// - Adds suffix "Input" for inputs.
String graphQLTypeNameFor(ClassElement2 clazz, {required bool isInput}) {
  final raw = clazz.name; // eg: BmcBddEmployee or BmcBddEmployeeInput

  var base = raw.startsWith('Bmc') ? raw.substring(3) : raw;

  if (isInput) {
    if (base.endsWith('Input')) {
      base = base.substring(0, base.length - 'Input'.length);
    }
    return '_${base}Input';
  }

  return base.startsWith('_') ? base : '_$base';
}

/// Resolves the JSON field name for a [field], taking into account
/// @JsonKey annotations and context overrides.
String jsonNameFor(FieldElement2 field, BuildContext ctx) {
  var name = ctx.resolveFieldName(field.name) ?? field.name;

  final ann = jsonKeyTypeChecker.firstAnnotationOf(field);
  if (ann != null) {
    final cr = ConstantReader(ann);
    final forced = cr.peek('name')?.stringValue;
    if (forced != null && forced.isNotEmpty) {
      name = forced;
    }
  }

  return name;
}

/// Builds the import path for a resolver function based on [clazz] and [fieldName].
String resolverImportFor(ClassElement2 clazz, String fieldName, {required String packageName}) {
  final typeSnake = ReCase(clazz.name).snakeCase; // ex: bmc_device_data
  final fieldSnake = ReCase(fieldName).snakeCase; // ex: booking_date_data
  return 'package:$packageName/graphql/resolvers/${typeSnake}_${fieldSnake}_resolver.dart';
}

/// Unwraps a `Future<T>` type and returns `T`.
/// If [t] is not a Future, returns [t] as-is.
DartType unwrapFuture(DartType t) {
  if (t is InterfaceType && t.typeArguments.isNotEmpty && t.element3.name == 'Future') {
    return t.typeArguments.first;
  }
  return t;
}

/// Resolves the GraphQL type expression for a Dart type [dartType],
/// handling async resolution for cross-type references.
/// Uses a cache to avoid duplicate async resolutions.
Future<Expression> graphQLTypeForDartType(
    ClassElement2 clazz,
    String memberName,
    DartType dartType,
    Resolver resolver, {
      required bool forInput,
      required Map<String, Future<Expression>> cache,
    }) async {
  final unwrapped = unwrapFuture(dartType);
  // Check if the type is a GraphQL class and is not the current class
  if (unwrapped is InterfaceType) {
    final typeName = unwrapped.element3.name;
    final isGraphQLClass = isTypeGraphQLClass(unwrapped);
    if (isGraphQLClass && typeName != clazz.name) {
      if (!cache.containsKey(typeName)) {
        // Asynchronously resolve the type of the other class.
        cache[typeName] = inferType(clazz.name, memberName, unwrapped, forInput, resolver);
      }
      return await cache[typeName]!;
    }
  }

  // For other types, use the standard inference logic
  return await inferType(clazz.name, memberName, unwrapped, forInput, resolver);
}

/// Special handling for input fields: allows `self` references
/// and `listOf(self)` for recursive input object types.
Future<Expression> graphQLTypeForInputField(
    ClassElement2 clazz,
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

  return await graphQLTypeForDartType(clazz, memberName, dartType, resolver, forInput: true, cache: cache);
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
      final inner = await inferType(className, name, arg, isInputType, resolver);
      return refer('listOf').call([inner]);
    }
  }

  // --- If not an InterfaceType, we can't resolve further ---
  if (type is! InterfaceType) {
    throw 'Cannot infer the GraphQL type for field $className.$name (type=$type).';
  }

  // --- Enums ---
  if (isTypeEnum(type)) {
    final rc = ReCase(type.element3.name);
    return refer('${rc.camelCase}GraphQLType');
  }

  // --- GraphQLClass (output) ---
  if (classTypeChecker.hasAnnotationOf(type.element3)) {
    var rawName = type.element3.name;
    if (serializableTypeChecker.hasAnnotationOf(type.element3) &&
        rawName.startsWith('_')) {
      rawName = rawName.substring(1);
    }
    final rc = ReCase(rawName);
    return refer('${rc.camelCase}GraphQLType');
  }

  // --- GraphQLInputClass (input) ---
  if (inputClassTypeChecker.hasAnnotationOf(type.element3)) {
    final rc = ReCase(type.element3.name);
    return refer('${rc.camelCase}InputGraphQLType');
  }

  // --- GraphQLUnion ---
  if (unionTypeChecker.hasAnnotationOf(type.element3)) {
    if (isInputType) {
      throw 'Union types are not allowed in input fields ($className.$name).';
    }
    final rc = ReCase(type.element3.name);
    return refer('${rc.camelCase}GraphQLType');
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

List<FieldElement2> collectFields(ClassElement2 clazz) {
  final fields = <FieldElement2>[];
  InterfaceType? search = clazz.thisType;

  while (search != null && !isTypeObject(search)) {
    for (final f in search.element3.fields2) {
      if (f.isStatic || f.isSynthetic) continue;
      if (fields.any((e) => e.name == f.name)) continue;
      fields.add(f);
    }
    search = search.superclass;
  }

  return fields;
}
