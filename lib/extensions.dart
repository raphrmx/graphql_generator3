import 'package:analyzer/dart/element/element2.dart';

extension Element2Compat on Element2 {
  String get name {
    return displayName;
  }
}

extension ClassElement2Compat on ClassElement2 {
  Iterable<FieldElement2> get fields {
    return fields2.where((f) => !f.isStatic && !f.isSynthetic);
  }

  ClassElement2? get superClass {
    return supertype?.element3 as ClassElement2?;
  }
}

extension EnumElement2Compat on EnumElement2 {
  Iterable<FieldElement2> get fields {
    return fields2.where((f) => f.isEnumConstant);
  }
}

extension MethodElement2Compat on MethodElement2 {
  String get name => displayName;
}

extension Element2DocCompat on Element2 {
  String? get documentationComment {
    final doc = this;
    return doc.documentationComment;
  }
}