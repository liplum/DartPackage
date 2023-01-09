import 'dart:convert';

import 'package:jconverter/jconverter.dart';
import 'package:test/test.dart';

void main() {
  group("Prototype of Custom JsonCodec", () {
    test("Map custom class", () {
      Object? reviver(Object? key, Object? value) {
        if (value is! Map) {
          return value;
        } else {
          return Foo(value["a"]);
        }
      }

      Object? toEncodable(dynamic object) {
        if (object is Foo) {
          return {"a": object.a};
        }
        return object;
      }

      final JsonCodec json = JsonCodec(reviver: reviver, toEncodable: toEncodable);
      final ta = Foo("toJson");
      final res = json.encode(ta);
      assert(res == '{"a":"toJson"}');
      const fa = '{"a":"fromJson"}';
      final res2 = json.decode(fa) as Foo;
      assert(res2.a == "fromJson");
    });
  });

  group("Test", () {
    final converter = JConverter();
    converter.enableMigration = true;
    final parentClz = Parent;
    converter.registerConvertibleAuto(parentClz.toString(), Parent.fromJson);
    final childClz = Child;
    converter.registerConvertibleAuto(childClz.toString(), Child.fromJson);
    test("toJson", () {
      const local = Parent('Liplum');
      final res = converter.toJson(local);
      assert(res != null);
      assert(res!.contains("Liplum"));
    });
    test("fromJson", () {
      const json = '{"name":"Liplum","@type":"Parent","@version":1}';
      final res = converter.fromJson<Parent>(json);
      assert(res != null);
      assert(res!.name == "Liplum");
    });
    test("polymorphism", () {
      const List<Parent> list = [
        Parent("Liplum"),
        Child("JConverter", 666),
      ];
      final res = converter.toJson(list);
      assert(res != null);
      assert(res!.contains("666"));
      final restored = converter.fromJson<List>(res);
      assert(restored != null);
      assert(restored![0] is Parent);
      assert((restored![1] as Child).extra == 666);
    });
    test("migration", () {
      const json =
          '[{"name":"Liplum","@type":"Parent","@version":1},{"name":"JConverter","extra":666,"@type":"Child","@version":1}]';
      converter.registerMigration(childClz.toString(), (origin, oldVersion) {
        if (oldVersion == 1) {
          origin["name"] = "MIGRATED";
        }
        return origin;
      });
      final restored = converter.fromJson<List>(json);
      assert(restored != null);
      assert(restored![0] is Parent);
      assert((restored![1] as Child).name == "MIGRATED");
      assert((restored![1] as Child).extra == 666);
    });
  });
  group("Stuff", () {
    test("Test generic inheritance checking", () {
      assert(isSubtype<String, JConvertibleProtocol>() == false);
      assert(isSubtype<Child, JConvertibleProtocol>() == true);
    });
  });
}

class Foo {
  final String a;

  Foo(this.a);
}

class Parent extends JConvertibleProtocol {
  final String name;

  const Parent(this.name);

  factory Parent.fromJson(Map<String, dynamic> json) {
    return Parent(
      json["name"],
    );
  }

  Map<String, dynamic> toJson() => {
        "name": name,
      };
}

class Child extends Parent {
  final int extra;

  const Child(super.name, this.extra);

  factory Child.fromJson(Map<String, dynamic> json) {
    return Child(
      json["name"],
      json["extra"],
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        "name": name,
        "extra": extra,
      };
}
