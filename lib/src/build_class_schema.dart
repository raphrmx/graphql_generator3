
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:angel3_serialize_generator/angel3_serialize_generator.dart' hide dateTimeTypeChecker;
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart';
import 'package:graphql_generator3/src/extensions.dart';
import 'package:graphql_generator3/src/type_checkers.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

import 'helpers.dart';

/// Builds a [Library] that defines either a `GraphQLObjectType` (for output)
/// or a `GraphQLInputObjectType` (for input) corresponding to the given Dart class.
///
/// This is the core of the GraphQL code generator. It inspects the [ClassElement2]
/// (the Dart class metadata) and produces the GraphQL schema representation
/// by generating a `final` top-level field with the appropriate GraphQL type.
///
/// ### Behavior
/// - If [isInputType] is `true`, generates a `GraphQLInputObjectType`:
///   - Collects fields from the class and its superclasses.
///   - Handles `@JsonKey` annotations to determine field names and inclusion.
///   - Resolves field types using [graphQLTypeForInputField].
///   - Handles self-references (recursive input types) by generating an
///     intermediate list of fields and an initializer function.
/// - If [isInputType] is `false`, generates a `GraphQLObjectType`:
///   - Collects fields and methods from the class and its superclasses.
///   - Fields are wrapped with resolvers that extract values either from
///     serialized maps or from Dart objects.
///   - Methods annotated with `@GraphQLResolver` are turned into GraphQL fields,
///     with parameter types and return types resolved automatically.
///   - Applies `@GraphQLDocumentation` and `@Deprecated` annotations to fields
///     and methods where available.
///   - Resolves implemented GraphQL interfaces and attaches them to the object type.
///
/// ### Parameters
/// - [clazz]: The Dart class to analyze and generate a GraphQL type for.
/// - [ctx]: A [BuildContext] with additional metadata, including naming strategies.
/// - [ann]: The annotation attached to the class (`@GraphQLClass` or `@GraphQLInputClass`).
/// - [isInputType]: Whether the generated type is for input (`true`) or output (`false`).
/// - [packageName]: Name of the Dart package where this class lives.
/// - [resolver]: The build resolver, used to resolve cross-library references.
///
/// ### Example (output type)
/// ```dart
/// @GraphQLClass()
/// class User {
///   final String id;
///   final String name;
/// }
///
/// // Generated:
/// final GraphQLObjectType userGraphQLType = objectType(
///   '_User',
///   fields: [
///     field('id', graphQLString.nonNullable),
///     field('name', graphQLString.nonNullable),
///   ],
/// );
/// ```
///
/// ### Example (input type)
/// ```dart
/// @GraphQLInputClass()
/// class UserInput {
///   final String name;
/// }
///
/// // Generated:
/// final GraphQLInputObjectType userInputGraphQLType = inputObjectType(
///   '_UserInput',
///   inputFields: [
///     GraphQLInputObjectField('name', graphQLString.nonNullable),
///   ],
/// );
/// ```
Future<Library> buildClassSchemaLibrary(
    ClassElement2 clazz,
    BuildContext? ctx,
    ConstantReader ann,
    bool isInputType, {
      required String packageName,
      required Resolver resolver,
    }) async {
  final resolvedTypesCache = <String, Future<Expression>>{};
  final typeName = graphQLTypeNameFor(clazz, isInput: isInputType);
  final args = <Expression>[literalString(typeName)];
  final named = <String, Expression>{};

  if (!isInputType) {
    named['isInterface'] = literalBool(isTypeInterface(clazz));
  }
  applyDescription(named, clazz);

  if (!isInputType) {
    final interfaces = clazz.interfaces.where(isTypeGraphQLClass).map((c) {
      var rawName = c.element3.name;
      if (serializableTypeChecker.hasAnnotationOf(c.element3) &&
          rawName.startsWith('_')) {
        rawName = rawName.substring(1);
      }
      final rc = ReCase(rawName);
      return refer('${rc.camelCase}GraphQLType');
    });
    named['interfaces'] = literalList(interfaces);
  }

  // Collecte les champs de la classe
  final collectedFields = <FieldElement2>[];
  InterfaceType? search = clazz.thisType;
  while (search != null && !isTypeObject(search)) {
    for (final f in search.element3.fields2) {
      if (f.isStatic || f.isSynthetic) continue;
      if (collectedFields.any((e) => e.name == f.name)) continue;
      collectedFields.add(f);
    }
    search = search.superclass;
  }

  final collectedMethods = <MethodElement2>[];
  InterfaceType? searchM = clazz.thisType;

  while (searchM != null && !isTypeObject(searchM)) {
    for (final m in searchM.element3.methods2) {
      if (m.isStatic) continue;
      if (!resolverTypeChecker.hasAnnotationOf(m)) continue;
      if (collectedMethods.any((x) => x.name == m.name)) continue;

      collectedMethods.add(m);
    }
    searchM = searchM.superclass;
  }

  // Construction des field specs
  final fieldSpecs = <Expression>[];
  final inputFieldSpecs = <Expression>[];

  for (final m in collectedMethods) {
    final namedArgs = <String, Expression>{};

    // Documentation et deprecation éventuelle
    applyDescription(namedArgs, m);
    final depAnn = deprecatedTypeChecker.firstAnnotationOf(m);
    if (depAnn != null) {
      final dep = ConstantReader(depAnn);
      final reason = dep.peek('message')?.stringValue ?? 'Deprecated.';
      namedArgs['deprecationReason'] = literalString(reason);
    }

    // Type de retour
    final returnGraphType = await graphQLTypeForDartType(
      clazz,
      m.name,
      m.returnType,
      resolver,
      forInput: false,
      cache: resolvedTypesCache,
    );

    // Paramètres → inputs GraphQL
    final inputExprs = <Expression>[];
    final funcType = m.type;
    for (final param in funcType.formalParameters) {
      final argName = param.name;
      final argType = param.type;

      final argGraphType = await graphQLTypeForDartType(
        clazz,
        '${m.name}.$argName',
        argType,
        resolver,
        forInput: true,
        cache: resolvedTypesCache,
      );

      inputExprs.add(
        refer('GraphQLFieldInput').call([literalString(argName), argGraphType]),
      );
    }

    // Accroche le resolver généré
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

    // Ajoute le field
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

  for (final f in collectedFields) {
    final namedArgs = <String, Expression>{};
    applyDescription(namedArgs, f);

    final depAnn = deprecatedTypeChecker.firstAnnotationOf(f);
    if (depAnn != null) {
      final dep = ConstantReader(depAnn);
      final reason = dep.peek('message')?.stringValue ?? 'Deprecated.';
      namedArgs['deprecationReason'] = literalString(reason);
    }

    Expression? graphType = await inferType(clazz.name, f.name, f.type, isInputType, resolver);

    if (f.type.nullabilitySuffix == NullabilitySuffix.none) {
      graphType = graphType?.property('nonNullable').call([]);
    }

    final jsonKeyName = jsonNameFor(f, ctx!);

    final isEnum = isTypeEnum(f.type);
    final listArg = iterableArg(f.type);
    final isListOfEnum = listArg != null && isTypeEnum(listArg);



    if (!isInputType) {
      String objRead = "(serialized as ${clazz.name}).${f.name}";
      if (isEnum) {
        objRead = "$objRead.toString().split('.').last";
      } else if (isListOfEnum) {
        objRead = "$objRead?.map((e) => e.toString().split('.').last).toList()";
      }
      final resolverCode = isEnum ? """
(serialized, args) {
  if (serialized is Map<String, dynamic>) {
    final raw = serialized['$jsonKeyName'] as String?;
    if (raw == null) return null;
    return ${f.type.element3!.name}.values.firstWhere(
      (e) => e.toString().split('.').last == raw,
      orElse: () => throw ArgumentError('Invalid enum ${f.type.element3!.name} value: \$raw'),
    );
  } else {
    return (serialized as ${clazz.name}).${f.name};
  }
}
""" : """
(serialized, args) => (serialized is Map<String, dynamic>) ? serialized['$jsonKeyName'] : $objRead
""";
      namedArgs['resolve'] = CodeExpression(Code(resolverCode));
    }

    if (isInputType) {
      final bool isRecursive = isSelfOrListOfSelf(f.type, clazz);

      final Expression fGraphType = isRecursive
          ? refer('t')
          : await graphQLTypeForInputField(
        clazz,
        f.name,
        f.type,
        resolver,
        cache: resolvedTypesCache,
      );

      inputFieldSpecs.add(
        refer('GraphQLInputObjectField').call(
          [literalString(jsonKeyName), fGraphType],
          namedArgs,
        ),
      );
    } else {
      // Output type
      fieldSpecs.add(
        refer('field').call(
          [literalString(jsonKeyName), graphType!],
          namedArgs,
        ),
      );
    }
  }

  final bool hasSelfRef =
      isInputType && collectedFields.any((f) => isSelfOrListOfSelf(f.type, clazz));

  // ========= Library build =========
  return Library((lb) {
    if (isInputType) {
      final typeIdent = '${ctx!.modelClassNameRecase.camelCase}InputGraphQLType';
      final sdlName = graphQLTypeNameFor(clazz, isInput: true);
      final desc = descriptionFor(clazz);

      if (hasSelfRef) {
        final typeIdent =
            '${ctx.modelClassNameRecase.camelCase}InputGraphQLType';
        final sdlName = graphQLTypeNameFor(clazz, isInput: true);
        final desc = descriptionFor(clazz);

        lb.body.add(
          Field((fb) {
            fb
              ..name = typeIdent
              ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
              ..type = refer('GraphQLInputObjectType')
              ..modifier = FieldModifier.final$
              ..assignment = Method((mb) {
                mb.body = Block.of([
                  // Création du type vide
                  declareFinal('t').assign(
                    refer('inputObjectType').call(
                      [literalString(sdlName)],
                      {
                        if (desc != null) 'description': literalString(desc),
                      },
                    ),
                  ).statement,

                  // Ajout des champs (avec literalList pour générer du code Dart correct)
                  refer('t')
                      .property('inputFields')
                      .property('addAll')
                      .call([literalList(inputFieldSpecs)])
                      .statement,

                  // Retour du type
                  refer('t').returned.statement,
                ]);
              }).closure.call([]).code;
          }),
        );
      } else {
        // Cas simple → direct avec inputFields
        lb.body.add(
          Field((fb) {
            fb
              ..name = typeIdent
              ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
              ..type = refer('GraphQLInputObjectType')
              ..modifier = FieldModifier.final$
              ..assignment = refer('inputObjectType').call(
                [literalString(sdlName)],
                {
                  if (desc != null) 'description': literalString(desc),
                  'inputFields': literalList(inputFieldSpecs),
                },
              ).code;
          }),
        );
      }
    } else {
      // Cas Output type
      final namedOut = Map<String, Expression>.from(named);
      namedOut['fields'] = literalList(fieldSpecs);
      lb.body.add(
        Field((fb) {
          fb
            ..name = '${ctx!.modelClassNameRecase.camelCase}GraphQLType'
            ..docs.add('/// Auto-generated from [${ctx.modelClassName}].')
            ..type = refer('GraphQLObjectType')
            ..modifier = FieldModifier.final$
            ..assignment = refer('objectType').call(args, namedOut).code;
        }),
      );
    }
  });
}
