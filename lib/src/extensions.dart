import 'package:analyzer/dart/element/element2.dart';

/// Provides a compatibility layer for [Element2],
/// exposing a simple `name` getter like the old `Element.name`.
extension Element2Compat on Element2 {
  String get name => displayName;
}

/// Adds convenience getters for [ClassElement2],
/// including non-static fields and the resolved superclass.
extension ClassElement2Compat on ClassElement2 {
  /// Returns only the instance fields (ignores static/synthetic ones).
  Iterable<FieldElement2> get fields =>
      fields2.where((f) => !f.isStatic && !f.isSynthetic);

  /// Returns the superclass of this class, if any.
  ClassElement2? get superClass =>
      supertype?.element3 as ClassElement2?;
}

/// Adds compatibility helpers for [EnumElement2],
/// making it easy to access only enum constants.
extension EnumElement2Compat on EnumElement2 {
  /// Returns the enum constant fields only.
  Iterable<FieldElement2> get fields =>
      fields2.where((f) => f.isEnumConstant);
}

/// Adds a `name` getter for [MethodElement2],
/// matching the legacy API from v1.
extension MethodElement2Compat on MethodElement2 {
  String get name => displayName;
}

/// Provides a way to fetch documentation comments from [Element2].
/// Works with class, enum, and interface elements.
extension Element2DocCompat on Element2 {
  /// Returns the documentation comment of this element, if available.
  /// Strips nothing — just returns the raw analyzer value.
  String? get documentationComment {
    final doc = this;
    if (doc is ClassElement2) {
      return doc.documentationComment;
    } else if (doc is EnumElement2) {
      return doc.documentationComment;
    } else if (doc is InterfaceElement2) {
      return doc.documentationComment;
    }
    return null;
  }
}
