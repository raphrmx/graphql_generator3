/// Annotate a class to generate a GraphQL input object type.
class GraphQLInputClass {
  const GraphQLInputClass();
}

class GraphQLResolver {
  const GraphQLResolver();
}

class GraphQLUnion {
  final List<Type> types;
  const GraphQLUnion({required this.types});
}