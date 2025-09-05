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
import 'package:graphql_annotation3/graphql_annotation3.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

var _docComment = RegExp(r'^/// ', multiLine: true);
var _graphQLDoc = TypeChecker.fromRuntime(GraphQLDocumentation);
var _graphQLClassTypeChecker = TypeChecker.fromRuntime(GraphQLClass);
var _graphQLInputClassTypeChecker = TypeChecker.fromRuntime(GraphQLInputClass);
var _graphQLResolverTypeChecker = TypeChecker.fromRuntime(GraphQLResolver);
var _graphQLUnionTypeChecker = TypeChecker.fromRuntime(GraphQLUnion);

bool _isEnumType(DartType t) =>
    t is InterfaceType && t.element is EnumElement;

bool _isIterable(DartType t) =>
    t is InterfaceType && TypeChecker.fromRuntime(Iterable).isAssignableFromType(t);

DartType? _iterableArg(DartType t) =>
    _isIterable(t) ? (t as InterfaceType).typeArguments.first : null;

/// Main generator, updated to handle both annotations.
Builder graphQLBuilder(_) {
  return SharedPartBuilder([
    _GraphQLGenerator(),
    _GraphQLInputGenerator(),
    _GraphQLUnionGenerator()
  ], 'graphql_generator3');
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
      final packageName = buildStep.inputId.package;
      var ctx = await buildContext(
        element,
        annotation,
        buildStep,
        buildStep.resolver,
        serializableTypeChecker.hasAnnotationOf(element),
      );
      // Call the build function with 'isInputType' set to 'false'
      var lib = _buildClassSchemaLibrary(element, ctx, annotation, false, packageName: packageName);
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
      final packageName = buildStep.inputId.package;
      var ctx = await buildContext(
        element,
        annotation,
        buildStep,
        buildStep.resolver,
        serializableTypeChecker.hasAnnotationOf(element),
      );
      // Call the build function with 'isInputType' set to 'true'
      var lib = _buildClassSchemaLibrary(element, ctx, annotation, true, packageName: packageName);
      return lib.accept(DartEmitter()).toString();
    }
    throw UnsupportedError('@GraphQLInputClass() is only supported on classes.');
  }
}

/// Generator for classes annotated with @GraphQLUnion (union types).
class _GraphQLUnionGenerator extends GeneratorForAnnotation<GraphQLUnion> {
  @override
  Future<String> generateForAnnotatedElement(
      Element element,
      ConstantReader annotation,
      BuildStep buildStep,
      ) async {
    if (element is! ClassElement) {
      throw UnsupportedError('@GraphQLUnion() is only supported on classes.');
    }

    // Nom Dart de l’union (ex: TestUnion)
    final unionDartName = element.name;
    final rc = _graphQLTypeNameFor(element, isInput: false);

    // Nom SDL attendu (ex: _TestUnion)
    final sdlName = annotation.peek('name')?.stringValue ?? _graphQLTypeNameFor(element, isInput: false);

    // On lit les "Type" littéraux de l'annotation
    final typeObjs = annotation.peek('types')?.listValue ?? const [];

    // Construit les identifiants "xxxGraphQLType" pour chaque membre
    final possibleTypeExprs = <Expression>[];

    for (final obj in typeObjs) {
      // IMPORTANT: pour un type literal, on récupère un DartType
      final dt = ConstantReader(obj).typeValue;

      // Récupère le nom simple de la classe (ex: BmcBddInvoiceTotal)
      final el = dt.element;
      if (el is! ClassElement) {
        // Par sécurité, on ignore tout ce qui ne serait pas une classe
        continue;
      }
      final dartTypeName = el.name;

      // Transforme en identifiant du GraphQLType généré (ex: bmcBddInvoiceTotalGraphQLType)
      final varIdent = '${ReCase(dartTypeName).camelCase}GraphQLType';
      possibleTypeExprs.add(refer(varIdent));
    }

    if (possibleTypeExprs.isEmpty) {
      // Évite de générer une union vide – erreur claire au build.
      throw InvalidGenerationSourceError(
        '@GraphQLUnion(types: [...]) on $unionDartName must contain at least one class type.',
        element: element,
      );
    }

    // Nom de la variable exportée pour l’union
    final unionVarName = '${ReCase(element.name).camelCase}GraphQLType';

    final lib = Library((b) {
      b.body.add(Field((f) {
        f
          ..docs.add('/// Auto-generated union from @$GraphQLUnion on $unionDartName.')
          ..name = unionVarName
          ..type = refer('GraphQLUnionType')
          ..modifier = FieldModifier.final$
        // GraphQLUnionType(name, Iterable<...> possibleTypes)
          ..assignment = refer('GraphQLUnionType').call(
            [
              literalString(sdlName),
              literalList(possibleTypeExprs),
            ],
          ).code;
      }));
    });

    return lib.accept(DartEmitter()).toString();
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
    bool isInputType, {
      required String packageName,
    }) {
  final resolverImports = <String>{};

  // Helpers locaux
  DartType unwrapFuture(DartType t) {
    if (t is InterfaceType && t.typeArguments.isNotEmpty && t.element.name == 'Future') {
      return t.typeArguments.first;
    }
    return t;
  }

  // fabrique l'expression de type GraphQL à partir d'un DartType,
  // en utilisant _inferType existant et en appliquant .nonNullable si nécessaire
  Expression graphQLTypeForDartType(
      String ownerName,
      String memberName,
      DartType dartType, {
        required bool forInput,
      }) {
    final unwrapped = unwrapFuture(dartType);
    var expr = _inferType(ownerName, memberName, unwrapped, forInput);
    if (unwrapped.nullabilitySuffix == NullabilitySuffix.none) {
      expr = expr.property('nonNullable').call([]);
    }
    return expr;
  }

  // Détecte si un type Dart correspond à la classe courante (auto-référence)
  bool isSelfType(DartType t) =>
      t is InterfaceType && t.element.name == clazz.name;

  bool isSelfOrListOfSelf(DartType t) {
    if (isSelfType(t)) return true;
    if (_isIterable(t)) {
      final a = _iterableArg(t);
      if (a != null && isSelfType(a)) return true;
    }
    return false;
  }

  // Construit l'expression GraphQL pour un champ d'INPUT en gérant self / list<self>
  Expression graphQLTypeForInputField(
      String ownerName,
      String memberName,
      DartType dartType,
      ) {
    // list<self> ?
    if (_isIterable(dartType)) {
      final arg = _iterableArg(dartType);
      if (arg != null && isSelfType(arg)) {
        var e = refer('listOf').call([refer('self')]);
        if (dartType.nullabilitySuffix == NullabilitySuffix.none) {
          e = e.property('nonNullable').call([]);
        }
        return e;
      }
    }

    // self ?
    if (isSelfType(dartType)) {
      Expression e = refer('self');
      if (dartType.nullabilitySuffix == NullabilitySuffix.none) {
        e = e.property('nonNullable').call([]);
      }
      return e;
    }

    // Sinon comme avant (input)
    return graphQLTypeForDartType(ownerName, memberName, dartType, forInput: true);
  }

  // Description “brute” pour inputObjectType
  String? descriptionFor(Element element) {
    var docString = element.documentationComment;
    if (docString == null && _graphQLDoc.hasAnnotationOf(element)) {
      final ann = _graphQLDoc.firstAnnotationOf(element);
      final cr = ConstantReader(ann);
      docString = cr.peek('description')?.stringValue;
    }
    if (docString == null) return null;
    return docString.replaceAll(_docComment, '').replaceAll('\n', '\\n');
  }

  // Prépare métadonnées communes
  final typeName = _graphQLTypeNameFor(clazz, isInput: isInputType);
  final args = <Expression>[literalString(typeName)];
  final named = <String, Expression>{};

  if (!isInputType) {
    named['isInterface'] = literalBool(isInterface(clazz));
  }
  _applyDescription(named, clazz, clazz.documentationComment);

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

  // ========= Collecte des champs (propriétés) y compris héritage =========
  final collectedFields = <FieldElement>[];
  InterfaceType? search = clazz.thisType;
  while (search != null && !TypeChecker.fromRuntime(Object).isExactlyType(search)) {
    for (final f in search.element.fields) {
      if (f.isStatic || f.isSynthetic) continue;
      if (collectedFields.any((e) => e.name == f.name)) continue;

      // Respect des @JsonKey(includeFromJson / includeToJson)
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

  // ========= Génération des champs =========
  // Pour les OUTPUTS : `fieldSpecs` (GraphQLObjectField)
  // Pour les INPUTS  : `inputFieldSpecs` (GraphQLInputObjectField) — remplis plus bas
  final fieldSpecs = <Expression>[];
  final inputFieldSpecs = <Expression>[];

  // --- 1) Propriétés ---
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
      final tn = cr.peek('typeName')?.symbolValue;
      if (tn != null) {
        graphType = refer(MirrorSystem.getName(tn));
      } else {
        graphType = _inferType(clazz.name, field.name, field.type, isInputType);
      }
    } else {
      graphType = _inferType(clazz.name, field.name, field.type, isInputType);
    }
    if (field.type.nullabilitySuffix == NullabilitySuffix.none) {
      graphType = graphType.property('nonNullable').call([]);
    }

    final jsonKeyName = _jsonNameFor(field, ctx!);

    if (isInputType) {
      final graphType = graphQLTypeForInputField(
        clazz.name,
        field.name,
        field.type,
      );
      // On remplit la liste "inputFieldSpecs" (qui sera injectée plus tard via addAll)
      inputFieldSpecs.add(
        refer('GraphQLInputObjectField').call(
          [literalString(jsonKeyName), graphType],
          namedArgs,
        ),
      );
    } else {
      // Output: field(...) + resolve (Map ou instance)
      final isDateTime = TypeChecker.fromRuntime(DateTime).isAssignableFromType(field.type);
      final isEnum = _isEnumType(field.type);
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
(serialized, args) {
  final v = (serialized is Map<String, dynamic>)
      ? (() { final m = serialized; return $mapRead; })()
      : (() { final o = serialized; return $objRead; })();
  return v;
}
""";
      namedArgs['resolve'] = CodeExpression(Code(resolverCode));

      fieldSpecs.add(
        refer('field').call(
          [literalString(jsonKeyName), graphType],
          namedArgs,
        ),
      );
    }
  }

  // --- 2) Méthodes @GraphQLResolver (OUTPUT uniquement) ---
  if (!isInputType) {
    final collectedMethods = <MethodElement>[];
    InterfaceType? searchM = clazz.thisType;
    while (searchM != null && !TypeChecker.fromRuntime(Object).isExactlyType(searchM)) {
      for (final m in searchM.element.methods) {
        if (m.isStatic) continue;
        if (!_graphQLResolverTypeChecker.hasAnnotationOf(m)) continue;
        if (collectedMethods.any((x) => x.name == m.name)) continue;
        collectedMethods.add(m);
      }
      searchM = searchM.superclass;
    }

    for (final m in collectedMethods) {
      final namedArgs = <String, Expression>{};

      _applyDescription(namedArgs, m, m.documentationComment);
      final depAnn = TypeChecker.fromRuntime(Deprecated).firstAnnotationOf(m);
      if (depAnn != null) {
        final dep = ConstantReader(depAnn);
        final reason = dep.peek('message')?.stringValue ?? 'Deprecated.';
        namedArgs['deprecationReason'] = literalString(reason);
      }

      final returnGraphType = graphQLTypeForDartType(
        clazz.name,
        m.name,
        m.returnType,
        forInput: false,
      );

      final inputExprs = <Expression>[];
      for (final p in m.parameters) {
        final argName = p.name;
        final argGraphType = graphQLTypeForDartType(
          clazz.name,
          '${m.name}.$argName',
          p.type,
          forInput: true,
        );

        inputExprs.add(
          refer('GraphQLFieldInput').call(
            [literalString(argName), argGraphType],
          ),
        );
      }

      final resolverImport = _resolverImportFor(clazz, m.name, packageName: packageName);
      resolverImports.add(resolverImport);

      final key = "${clazz.name}.${m.name}";
      final registryCall = """
(serialized, args) {
  final r = resolverRegistry['$key'];
  if (r == null) {
    throw StateError('Missing resolver for $key');
  }
  return r(serialized, args);
}
""";
      namedArgs['resolve'] = CodeExpression(Code(registryCall));

      fieldSpecs.add(
        refer('field').call(
          [literalString(m.name), returnGraphType],
          {
            ...namedArgs,
            if (inputExprs.isNotEmpty) 'inputs': literalList(inputExprs),
          },
        ),
      );
    }
  }

  final bool hasSelfRef = isInputType && collectedFields.any((f) => isSelfOrListOfSelf(f.type));

  // ========= Construction du Library =========
  return Library((lb) {
    if (isInputType) {
      final typeIdent  = '${ctx!.modelClassNameRecase.camelCase}InputGraphQLType';
      final sdlName    = _graphQLTypeNameFor(clazz, isInput: true);
      final desc       = descriptionFor(clazz);

      if (!hasSelfRef) {
        // ---- CAS SIMPLE: pas d’auto-référence -> liste directe (pas d’IIFE) ----
        final namedDirect = Map<String, Expression>.from(named)
          ..['inputFields'] = literalList(inputFieldSpecs);

        lb.body.add(Field((fb) {
          fb
            ..name = typeIdent
            ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
            ..type = refer('GraphQLInputObjectType')
            ..modifier = FieldModifier.final$
            ..assignment = refer('inputObjectType')
                .call(
              [literalString(sdlName)],
              {
                if (desc != null) 'description': literalString(desc),
                ...namedDirect,
              },
            )
                .code;
        }));

      } else {
        // ---- CAS AUTO-RÉFÉRENCE: IIFE + self ----
        final fieldsVar  = '_${ctx.modelClassNameRecase.camelCase}InputFields';
        final initFn     = '_init${ctx.modelClassNameRecase.pascalCase}InputFields';

        // 1) liste partagée
        lb.body.add(Field((fb) {
          fb
            ..name = fieldsVar
            ..modifier = FieldModifier.final$
            ..type = TypeReference((t) => t
              ..symbol = 'List'
              ..types.add(
                TypeReference((tt) => tt
                  ..symbol = 'GraphQLInputObjectField'
                  ..types.add(refer('dynamic'))
                  ..types.add(refer('dynamic')),
                ),
              ))
            ..assignment = Code('<GraphQLInputObjectField<dynamic, dynamic>>[]');
        }));

        // 2) init(self) -> addAll(...)
        lb.body.add(Method((mb) {
          mb
            ..name = initFn
            ..returns = refer('void')
            ..requiredParameters.add(
              Parameter((p) => p
                ..name = 'self'
                ..type = refer('GraphQLInputObjectType'),
              ),
            )
            ..body = Block.of([
              refer(fieldsVar)
                  .property('addAll')
                  .call([literalList(inputFieldSpecs)])
                  .statement,
            ]);
        }));

        // 3) IIFE qui crée le type et appelle l’init
        final iife = StringBuffer();
        iife.writeln('(() {');
        if (desc != null) {
          iife.writeln(
              "  final t = inputObjectType('$sdlName', description: '$desc', inputFields: $fieldsVar);");
        } else {
          iife.writeln(
              "  final t = inputObjectType('$sdlName', inputFields: $fieldsVar);");
        }
        iife.writeln('  $initFn(t);');
        iife.writeln('  return t;');
        iife.writeln('})()');

        lb.body.add(Field((fb) {
          fb
            ..name = typeIdent
            ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
            ..type = refer('GraphQLInputObjectType')
            ..modifier = FieldModifier.final$
            ..assignment = Code(iife.toString());
        }));
      }

    } else {
      // ----- OUTPUT ----- (inchangé)
      final namedOut = Map<String, Expression>.from(named);
      namedOut['fields'] = literalList(fieldSpecs);
      lb.body.add(Field((fb) {
        fb
          ..name = '${ctx!.modelClassNameRecase.camelCase}GraphQLType'
          ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
          ..type = refer('GraphQLObjectType')
          ..modifier = FieldModifier.final$
          ..assignment = refer('objectType').call(args, namedOut).code;
      }));
    }
  });
}

// Updated inference function to recognize input types
Expression _inferType(String className, String name, DartType type, bool isInputType) {
  if (type is InterfaceType) {
    if (_graphQLUnionTypeChecker.hasAnnotationOf(type.element)) {
      if (isInputType) {
        throw 'Union types are not allowed in input fields ($className.$name).';
      }
      final rc = ReCase(type.element.name); // ex: BmcTestUnion
      return refer('${rc.camelCase}GraphQLType'); // -> bmcTestUnionGraphQLType
    }

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

  if (type is InterfaceType &&
      type.typeArguments.isNotEmpty &&
      TypeChecker.fromRuntime(Iterable).isAssignableFromType(type)) {
    final arg = type.typeArguments[0];
    final inner = _inferType(className, name, arg, isInputType);
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

// Helper commun pour fabriquer le nom GraphQL
String _graphQLTypeNameFor(ClassElement clazz, {required bool isInput}) {
  final raw = clazz.name; // ex: BmcBddEmployee ou BmcBddEmployeeInput

  // retire le préfixe Bmc
  var base = raw.startsWith('Bmc') ? raw.substring(3) : raw;

  if (isInput) {
    // retire le suffixe Input (s’il est présent)
    if (base.endsWith('Input')) {
      base = base.substring(0, base.length - 'Input'.length);
    }
    // ajoute underscore + remet Input
    return '_${base}Input';
  }

  // ajoute underscore devant pour les outputs
  return base.startsWith('_') ? base : '_$base';
}

String _resolverImportFor(ClassElement clazz, String fieldName, {required String packageName}) {
  final typeSnake = ReCase(clazz.name).snakeCase;    // ex: bmc_device_data
  final fieldSnake = ReCase(fieldName).snakeCase;    // ex: booking_date_data
  return 'package:$packageName/graphql/resolvers/${typeSnake}_${fieldSnake}_resolver.dart';
}

String _resolverFnFor(ClassElement clazz, String fieldName) {
  final typeCamel  = ReCase(clazz.name).camelCase;   // bmcDeviceData
  final fieldPascal = ReCase(fieldName).pascalCase;  // BookingDateData
  return '${typeCamel}${fieldPascal}Resolver';       // bmcDeviceDataBookingDateDataResolver
}
