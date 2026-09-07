import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:graphql_generator3/graphql_generator3.dart';
import 'package:test/test.dart';

/// Stubs of the two annotation libraries the generator recognises. They are
/// matched by URL, so only the paths and the shapes of the annotations matter:
/// the tests stay hermetic and need neither package resolved from git nor pub.
const _stubs = <String, String>{
  'graphql_schema3|lib/graphql_schema3.dart': "export 'src/schema.dart';",
  'graphql_schema3|lib/src/schema.dart': '''
const GraphQLClass graphQLClass = GraphQLClass._();

class GraphQLClass {
  const GraphQLClass._();
}

class GraphQLInputClass {
  const GraphQLInputClass();
}

class GraphQLUnion {
  final List<Type> types;
  const GraphQLUnion({required this.types});
}

class GraphQLSkip {
  const GraphQLSkip();
}

const graphQLSkip = GraphQLSkip();

class GraphQLResolver {
  const GraphQLResolver();
}

class GraphQLDocumentation {
  final String? description;
  final String? deprecationReason;
  const GraphQLDocumentation({this.description, this.deprecationReason});
}
''',
  'json_annotation|lib/json_annotation.dart': "export 'src/json_key.dart';",
  'json_annotation|lib/src/json_key.dart': '''
class JsonKey {
  final String? name;
  const JsonKey({this.name});
}
''',
};

/// Runs the builder over [source] and returns the generated part, with runs of
/// whitespace collapsed so the assertions do not depend on the formatter.
Future<String> generate(String source) async {
  final logs = <String>[];
  final result = await testBuilder(
    graphQLBuilder(BuilderOptions.empty),
    {..._stubs, 'a|lib/fixture.dart': source},
    generateFor: {'a|lib/fixture.dart'},
    // Keep the generated part addressable by its own asset id.
    flattenOutput: true,
    onLog: (record) {
      // 900 is `Level.WARNING`; naming it would pull in package:logging.
      if (record.level.value >= 900) {
        logs.add('${record.message} ${record.error ?? ''}');
      }
    },
  );

  expect(logs, isEmpty, reason: 'The builder logged a warning or worse.');

  final id = AssetId('a', 'lib/fixture.graphql_generator3.g.part');
  if (!result.readerWriter.testing.exists(id)) return '';

  // Collapse the formatter's line breaks so the assertions read as one line
  // and do not have to be revisited every time dart_format changes its mind.
  return result.readerWriter.testing
      .readString(id)
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('( ', '(')
      .replaceAll(' )', ')')
      .replaceAll('[ ', '[')
      .replaceAll(', ]', ']')
      .replaceAll(' ]', ']')
      .replaceAll(', )', ')')
      .replaceAll(',)', ')')
      .trim();
}

const _header = '''
import 'package:graphql_schema3/graphql_schema3.dart';
import 'package:json_annotation/json_annotation.dart';
''';

void main() {
  group('object types', () {
    test('generates one objectType per annotated class', () async {
      final out = await generate('''
$_header
@graphQLClass
class Company {
  final String vatNo;
  Company(this.vatNo);
}
''');

      expect(out, contains('final GraphQLObjectType companyGraphQLType'));
      expect(out, contains("objectType('_Company'"));
      expect(out, contains("field('vatNo', graphQLString.nonNullable()"));
    });

    test(
      'strips the Bmc prefix from the SDL name but not from the variable',
      () async {
        final out = await generate('''
$_header
@graphQLClass
class BmcBddEmployee {
  final String name;
  BmcBddEmployee(this.name);
}
''');

        expect(out, contains('bmcBddEmployeeGraphQLType'));
        expect(out, contains("objectType('_BddEmployee'"));
      },
    );

    test('marks an abstract class as an interface', () async {
      final out = await generate('''
$_header
@graphQLClass
abstract class BaseModel {
  final String id;
  BaseModel(this.id);
}
''');

      expect(out, contains('isInterface: true'));
    });

    test('lists the GraphQL interfaces a class implements', () async {
      final out = await generate('''
$_header
@graphQLClass
abstract class Identified {
  final String id;
  Identified(this.id);
}

@graphQLClass
class Company implements Identified {
  @override
  final String id;
  Company(this.id);
}
''');

      expect(out, contains('interfaces: [identifiedGraphQLType]'));
    });

    test('maps the Dart primitives onto the GraphQL scalars', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  final String s;
  final int i;
  final double d;
  final bool b;
  final DateTime t;
  Sample(this.s, this.i, this.d, this.b, this.t);
}
''');

      expect(out, contains("field('s', graphQLString"));
      expect(out, contains("field('i', graphQLInt"));
      expect(out, contains("field('d', graphQLFloat"));
      expect(out, contains("field('b', graphQLBoolean"));
      expect(out, contains("field('t', graphQLDate"));
    });

    test('wraps a nullable field without nonNullable', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  final String? maybe;
  final String surely;
  Sample(this.maybe, this.surely);
}
''');

      expect(out, contains("field('maybe', graphQLString,"));
      expect(out, contains("field('surely', graphQLString.nonNullable()"));
    });

    test('wraps an iterable field in listOf', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  final List<String> tags;
  Sample(this.tags);
}
''');

      expect(out, contains("listOf(graphQLString)"));
    });

    test('carries the doc comment over as a description', () async {
      final out = await generate('''
$_header
/// The company as the backoffice knows it.
@graphQLClass
class Company {
  /// VAT number, unique.
  final String vatNo;
  Company(this.vatNo);
}
''');

      expect(
        out,
        contains("description: 'The company as the backoffice knows it.'"),
      );
      expect(out, contains("description: 'VAT number, unique.'"));
    });

    test('carries a deprecation over as a deprecationReason', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  @Deprecated('Use vatNo instead.')
  final String enterpriseNumber;
  Sample(this.enterpriseNumber);
}
''');

      expect(out, contains("deprecationReason: 'Use vatNo instead.'"));
    });

    test('skips a static field and a getter-induced one', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  static const String constant = 'x';
  final String kept;
  Sample(this.kept);
  String get computed => kept;
}
''');

      expect(out, contains("field('kept'"));
      expect(out, isNot(contains("'constant'")));
      expect(out, isNot(contains("'computed'")));
    });

    test('honours @GraphQLSkip on a field', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  final String kept;
  @graphQLSkip
  final String hidden;
  Sample(this.kept, this.hidden);
}
''');

      expect(out, contains("field('kept'"));
      expect(out, isNot(contains("'hidden'")));
    });

    test('collects the fields declared on a superclass', () async {
      final out = await generate('''
$_header
class BaseModel {
  final String id;
  BaseModel(this.id);
}

@graphQLClass
class Company extends BaseModel {
  final String vatNo;
  Company(this.vatNo, String id) : super(id);
}
''');

      expect(out, contains("field('vatNo'"));
      expect(out, contains("field('id'"));
    });
  });

  group('JSON naming', () {
    test('serializes a field under its Dart name by default', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  final String companyAccount;
  Sample(this.companyAccount);
}
''');

      expect(out, contains("field('companyAccount'"));
      expect(out, contains("serialized['companyAccount']"));
    });

    test('honours @JsonKey(name:)', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  @JsonKey(name: 'company_account')
  final String companyAccount;
  Sample(this.companyAccount);
}
''');

      expect(out, contains("field('company_account'"));
      expect(out, contains("serialized['company_account']"));
      expect(out, contains('.companyAccount'));
    });

    test('ignores an empty @JsonKey name', () async {
      final out = await generate('''
$_header
@graphQLClass
class Sample {
  @JsonKey(name: '')
  final String companyAccount;
  Sample(this.companyAccount);
}
''');

      expect(out, contains("field('companyAccount'"));
    });
  });

  group('enums', () {
    test('generates a GraphQLEnumType from the enum constants', () async {
      final out = await generate('''
$_header
/// How a licence is billed.
@graphQLClass
enum BillingCycle {
  /// Every month.
  monthly,
  yearly,
}
''');

      expect(
        out,
        contains('final GraphQLEnumType<BillingCycle> billingCycleGraphQLType'),
      );
      expect(
        out,
        contains(
          "GraphQLEnumValue('monthly', BillingCycle.monthly, description: 'Every month.')",
        ),
      );
      expect(out, contains("GraphQLEnumValue('yearly', BillingCycle.yearly)"));
      expect(out, contains("description: 'How a licence is billed.'"));
      expect(out, contains("description: 'Every month.'"));
      expect(out, isNot(contains("'values'")));
      expect(out, isNot(contains("'index'")));
    });

    test('resolves an enum field through its generated type', () async {
      final out = await generate('''
$_header
@graphQLClass
enum BillingCycle { monthly }

@graphQLClass
class Sample {
  final BillingCycle cycle;
  Sample(this.cycle);
}
''');

      expect(out, contains("field('cycle', billingCycleGraphQLType"));
      expect(out, contains('BillingCycle.values.firstWhere'));
    });
  });

  group('input types', () {
    test('generates an inputObjectType for @GraphQLInputClass', () async {
      final out = await generate('''
$_header
@GraphQLInputClass()
class CompanyInput {
  final String vatNo;
  CompanyInput(this.vatNo);
}
''');

      expect(
        out,
        contains('final GraphQLInputObjectType companyInputInputGraphQLType'),
      );
      expect(out, contains("inputObjectType('_CompanyInput'"));
      expect(out, contains("GraphQLInputObjectField('vatNo'"));
    });

    test('refers to itself through a closure for a recursive input', () async {
      final out = await generate('''
$_header
@GraphQLInputClass()
class NodeInput {
  final List<NodeInput>? children;
  NodeInput(this.children);
}
''');

      expect(out, contains('t.inputFields.addAll'));
      expect(out, contains("GraphQLInputObjectField('children', t)"));
    });
  });

  group('unions', () {
    test('generates a GraphQLUnionType over the listed types', () async {
      final out = await generate('''
$_header
@graphQLClass
class Dog {
  final String name;
  Dog(this.name);
}

@graphQLClass
class Cat {
  final String name;
  Cat(this.name);
}

@GraphQLUnion(types: [Dog, Cat])
class Animal {}
''');

      expect(out, contains('final GraphQLUnionType animalGraphQLType'));
      expect(
        out,
        contains(
          "GraphQLUnionType('_Animal', [dogGraphQLType, catGraphQLType])",
        ),
      );
    });
  });

  group('resolvers', () {
    test('routes an annotated method through the resolver registry', () async {
      final out = await generate('''
$_header
@graphQLClass
class Company {
  final String vatNo;
  Company(this.vatNo);

  @GraphQLResolver()
  Future<String> label(String prefix) async => prefix;
}
''');

      expect(out, contains("field('label', graphQLString"));
      expect(out, contains("resolverRegistry['Company.label']"));
      expect(out, contains("GraphQLFieldInput('prefix', graphQLString"));
    });
  });
}
