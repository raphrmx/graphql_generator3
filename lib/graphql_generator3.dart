import 'dart:async';
import 'dart:mirrors';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:angel3_model/angel3_model.dart';
import 'package:angel3_serialize_generator/angel3_serialize_generator.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

import 'graphql_annotations.dart';
export 'graphql_annotations.dart';

var _docComment = RegExp(r'^/// ', multiLine: true);
var _graphQLDoc = TypeChecker.fromRuntime(GraphQLDocumentation);
var _graphQLClassTypeChecker = TypeChecker.fromRuntime(GraphQLClass);
var _graphQLInputClassTypeChecker = TypeChecker.fromRuntime(GraphQLInputClass);

bool _isEnumType(DartType t) =>
    t is InterfaceType && t.element is EnumElement;

bool _isIterable(DartType t) =>
    t is InterfaceType && TypeChecker.fromRuntime(Iterable).isAssignableFromType(t);

DartType? _iterableArg(DartType t) =>
    _isIterable(t) ? (t as InterfaceType).typeArguments.first : null;

/// Main generator, updated to handle both annotations.
Builder graphQLBuilder(_) {
  return SharedPartBuilder([
    _GraphQLGenerator(), // Generator for output types
    _GraphQLInputGenerator() // New generator for input types
  ], 'graphql_generator2');
}

/// Generator for classes annotated with @GraphQLClass (output types).
class _GraphQLGenerator extends GeneratorForAnnotation<GraphQLClass> {
  @override
  Future<String> generateForAnnotatedElement(
      Element element,
      ConstantReader annotation,
      BuildStep buildStep,
      ) async {
    if (element is ClassElement) {
      var ctx = await buildContext(
        element,
        annotation,
        buildStep,
        buildStep.resolver,
        serializableTypeChecker.hasAnnotationOf(element),
      );
      // Call the build function with 'isInputType' set to 'false'
      var lib = _buildClassSchemaLibrary(element, ctx, annotation, false);
      return lib.accept(DartEmitter()).toString();
    }
    if (element is EnumElement) {
      var lib = _buildEnumSchemaLibrary(element, annotation);
      return lib.accept(DartEmitter()).toString();
    }
    throw UnsupportedError('@GraphQLClass() is only supported on classes or enums.');
  }
}

/// New generator for classes annotated with @GraphQLInputClass (input types).
class _GraphQLInputGenerator extends GeneratorForAnnotation<GraphQLInputClass> {
  @override
  Future<String> generateForAnnotatedElement(
      Element element,
      ConstantReader annotation,
      BuildStep buildStep,
      ) async {
    if (element is ClassElement) {
      var ctx = await buildContext(
        element,
        annotation,
        buildStep,
        buildStep.resolver,
        serializableTypeChecker.hasAnnotationOf(element),
      );
      // Call the build function with 'isInputType' set to 'true'
      var lib = _buildClassSchemaLibrary(element, ctx, annotation, true);
      return lib.accept(DartEmitter()).toString();
    }
    throw UnsupportedError('@GraphQLInputClass() is only supported on classes.');
  }
}

// The library building functions are now shared
Library _buildEnumSchemaLibrary(EnumElement clazz, ConstantReader ann) {
  return Library((b) {
    b.body.add(Field((b) {
      var args = <Expression>[literalString(clazz.name)];
      var values = clazz.fields.where((f) => f.isEnumConstant).map((f) => f.name);
      var named = <String, Expression>{};
      _applyDescription(named, clazz, clazz.documentationComment);
      args.add(literalConstList(values.map(literalString).toList()));
      b
        ..name = '${ReCase(clazz.name).camelCase}GraphQLType'
        ..docs.add('/// Auto-generated from [${clazz.name}].')
        ..type = TypeReference((b) => b
          ..symbol = 'GraphQLEnumType'
          ..types.add(refer('String')))
        ..modifier = FieldModifier.final$
        ..assignment = refer('enumTypeFromStrings').call(args, named).code;
    }));
  });
}

Library _buildClassSchemaLibrary(
    ClassElement clazz,
    BuildContext? ctx,
    ConstantReader ann,
    bool isInputType, // The new 'isInputType' parameter
    ) {
  return Library((b) {
    b.body.add(Field((b) {
      final args = <Expression>[literalString(ctx!.modelClassName!)];
      final named = <String, Expression>{};

      // Input types cannot be interfaces
      if (!isInputType) {
        named['isInterface'] = literalBool(isInterface(clazz));
      }

      // Class description
      _applyDescription(named, clazz, clazz.documentationComment);

      // Interfaces (output types only)
      if (!isInputType) {
        final interfaces = clazz.interfaces.where(_isGraphQLClass).map((c) {
          var rawName = c.element.name;
          if (serializableTypeChecker.hasAnnotationOf(c.element) && rawName.startsWith('_')) {
            rawName = rawName.substring(1);
          }
          final rc = ReCase(rawName);
          return refer('${rc.camelCase}GraphQLType');
        });
        named['interfaces'] = literalList(interfaces);
      }

      // Collect fields (including inheritance)
      final collectedFields = <FieldElement>[];
      InterfaceType? search = clazz.thisType;
      while (search != null && !TypeChecker.fromRuntime(Object).isExactlyType(search)) {
        for (final f in search.element.fields) {
          if (f.isStatic || f.isSynthetic) continue;
          if (collectedFields.any((e) => e.name == f.name)) continue;
          final jsonKeyAnn = const TypeChecker.fromRuntime(JsonKey).firstAnnotationOf(f);
          if (jsonKeyAnn != null) {
            final cr = ConstantReader(jsonKeyAnn);
            final incFrom = cr.peek('includeFromJson')?.boolValue;
            final incTo = cr.peek('includeToJson')?.boolValue;
            if (incFrom == false && incTo == false) continue;
          }
          collectedFields.add(f);
        }
        search = search.superclass;
      }

      // GraphQL field generation
      final fields = <Expression>[];
      for (final field in collectedFields) {
        final namedArgs = <String, Expression>{};
        _applyDescription(namedArgs, field, field.documentationComment);
        final depAnn = TypeChecker.fromRuntime(Deprecated).firstAnnotationOf(field);
        if (depAnn != null) {
          final dep = ConstantReader(depAnn);
          final reason = dep.peek('message')?.stringValue ?? 'Deprecated.';
          namedArgs['deprecationReason'] = literalString(reason);
        }

        Expression graphType;
        final explicitDoc = _graphQLDoc.firstAnnotationOf(field);
        if (explicitDoc != null) {
          final cr = ConstantReader(explicitDoc);
          final typeName = cr.peek('typeName')?.symbolValue;
          if (typeName != null) {
            graphType = refer(MirrorSystem.getName(typeName));
          } else {
            // Pass 'isInputType' to the inference function
            graphType = _inferType(clazz.name, field.name, field.type, isInputType);
          }
        } else {
          // Pass 'isInputType' to the inference function
          graphType = _inferType(clazz.name, field.name, field.type, isInputType);
        }
        if (field.type.nullabilitySuffix == NullabilitySuffix.none) {
          graphType = graphType.property('nonNullable').call([]);
        }

        final jsonKeyName = _jsonNameFor(field, ctx);

        // Condition to generate either an output field or an input field
        if (isInputType) {
          // CHANGE 1: Use 'GraphQLInputObjectField' for input fields.
          fields.add(
            refer('GraphQLInputObjectField').call(
              [literalString(jsonKeyName), graphType],
              namedArgs,
            ),
          );
        } else {
          final isDateTime = TypeChecker.fromRuntime(DateTime).isAssignableFromType(field.type);
          final isEnum = _isEnumType(field.type);
          final isList = _isIterable(field.type);
          final listArg = _iterableArg(field.type);
          final isListOfEnum = listArg != null && _isEnumType(listArg);

          String mapRead;
          if (isDateTime) {
            mapRead = "(m['$jsonKeyName'] == null ? null : DateTime.parse(m['$jsonKeyName'] as String))";
          } else {
            mapRead = "m['$jsonKeyName']";
          }
          final className = clazz.name;
          String objRead = "(o as $className).${field.name}";
          if (isEnum) {
            objRead = "$objRead.toString().split('.').last";
          } else if (isListOfEnum) {
            objRead = "$objRead?.map((e) => e.toString().split('.').last).toList()";
          }
          final resolverCode = """
(obj, ctx) {
  final v = (obj is Map<String, dynamic>)
      ? (() { final m = obj; return $mapRead; })()
      : (() { final o = obj; return $objRead; })();
  return v;
}
""";
          namedArgs['resolve'] = CodeExpression(Code(resolverCode));

          fields.add(
            refer('field').call(
              [literalString(jsonKeyName), graphType],
              namedArgs,
            ),
          );
        }
      }

      // CHANGE 2: Use 'inputFields' for input types.
      if (isInputType) {
        named['inputFields'] = literalList(fields);
      } else {
        named['fields'] = literalList(fields);
      }

      // Final condition to generate the correct object type
      if (isInputType) {
        b
          ..name = '${ctx.modelClassNameRecase.camelCase}InputGraphQLType'
          ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
          ..type = refer('GraphQLInputObjectType')
          ..modifier = FieldModifier.final$
          ..assignment = refer('inputObjectType').call(args, named).code;
      } else {
        b
          ..name = '${ctx.modelClassNameRecase.camelCase}GraphQLType'
          ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
          ..type = refer('GraphQLObjectType')
          ..modifier = FieldModifier.final$
          ..assignment = refer('objectType').call(args, named).code;
      }
    }));
  });
}

// Updated inference function to recognize input types
Expression _inferType(String className, String name, DartType type, bool isInputType) {
  if (type is InterfaceType) {
    // If the class is a @GraphQLInputClass, reference its input type.
    if (_graphQLInputClassTypeChecker.hasAnnotationOf(type.element)) {
      final c = type;
      final rc = ReCase(c.element.name);
      return refer('${rc.camelCase}InputGraphQLType');
    }
    // If the class is a @GraphQLClass, reference its output type.
    if (_isGraphQLClass(type)) {
      final c = type;
      var rawName = c.element.name;
      if (serializableTypeChecker.hasAnnotationOf(c.element) && rawName.startsWith('_')) {
        rawName = rawName.substring(1);
      }
      final rc = ReCase(rawName);
      return refer('${rc.camelCase}GraphQLType');
    }
  }

  // Inference logic for primitive types and lists (unchanged)
  if (TypeChecker.fromRuntime(Model).isAssignableFromType(type) && name == 'id') {
    return refer('graphQLId');
  }

  var primitive = {
    String: 'graphQLString',
    int: 'graphQLInt',
    double: 'graphQLFloat',
    bool: 'graphQLBoolean',
    DateTime: 'graphQLDate'
  };

  for (var entry in primitive.entries) {
    if (TypeChecker.fromRuntime(entry.key).isAssignableFromType(type)) {
      return refer(entry.value);
    }
  }

  if (type is InterfaceType && type.typeArguments.isNotEmpty && TypeChecker.fromRuntime(Iterable).isAssignableFromType(type)) {
    var arg = type.typeArguments[0];
    // Pass 'isInputType' recursively
    var inner = _inferType(className, name, arg, isInputType);
    return refer('listOf').call([inner]);
  }

  throw 'Cannot infer the GraphQL type for field $className.$name (type=$type).';
}

bool isInterface(ClassElement clazz) {
  return clazz.isAbstract && !serializableTypeChecker.hasAnnotationOf(clazz);
}

bool _isGraphQLClass(InterfaceType clazz) {
  InterfaceType? search = clazz;
  while (search != null) {
    if (_graphQLClassTypeChecker.hasAnnotationOf(search.element)) {
      return true;
    }
    search = search.superclass;
  }
  return false;
}

void _applyDescription(Map<String, Expression> named, Element element, String? docComment) {
  var docString = docComment;
  if (docString == null && _graphQLDoc.hasAnnotationOf(element)) {
    var ann = _graphQLDoc.firstAnnotationOf(element);
    var cr = ConstantReader(ann);
    docString = cr.peek('description')?.stringValue;
  }
  if (docString != null) {
    named['description'] = literalString(docString.replaceAll(_docComment, '').replaceAll('\n', '\\n'));
  }
}

String _jsonNameFor(FieldElement field, BuildContext ctx) {
  var name = ctx.resolveFieldName(field.name) ?? field.name;

  final ann = const TypeChecker.fromRuntime(JsonKey).firstAnnotationOf(field);
  if (ann != null) {
    final cr = ConstantReader(ann);
    final forced = cr.peek('name')?.stringValue;
    if (forced != null && forced.isNotEmpty) {
      name = forced;
    }
  }

  return name;
}