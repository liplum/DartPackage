import 'dart:convert';

/// Extends this class to get default behaviour.
abstract class JConvertibleProtocol {
  const JConvertibleProtocol();

  String get typeName => runtimeType.toString();

  int get version => 1;
}

typedef ToJsonFunc<T> = Map<String, dynamic> Function(T obj);
typedef FromJsonFunc<T> = T Function(Map<String, dynamic> json);
typedef Migration = Map<dynamic, dynamic> Function(Map<dynamic, dynamic> origin, int oldVersion);

abstract class JConverterKeys {
  String get type;

  String get version;
}

class _DefaultConvertKeysImpl implements JConverterKeys {
  const _DefaultConvertKeysImpl();

  @override
  String get type => "@type";

  @override
  String get version => "@version";
}

const _defaultConvertKeys = _DefaultConvertKeysImpl();

bool isSubtype<Child, Parent>() => <Child>[] is List<Parent>;
dynamic directConvertFunc(dynamic any) => any;

abstract class ConverterLoggerProtocol {
  void error(dynamic message, dynamic error, StackTrace? stackTrace);

  void info(String message);
}

class JConverterLogger implements ConverterLoggerProtocol {
  final void Function(dynamic message, dynamic error, StackTrace? stackTrace)? onError;
  final void Function(String message)? onInfo;

  const JConverterLogger({
    this.onError,
    this.onInfo,
  });

  @override
  void error(message, error, StackTrace? stackTrace) {
    onError?.call(message, error, stackTrace);
  }

  @override
  void info(String message) {
    onInfo?.call(message);
  }
}

class _ConvertibleProtocolEntry {
  final ToJsonFunc? toJson;
  final FromJsonFunc fromJson;

  const _ConvertibleProtocolEntry(this.toJson, this.fromJson);
}

class _TypeEntry {
  final String typeName;
  final int version;
  final ToJsonFunc? toJson;
  final FromJsonFunc fromJson;

  const _TypeEntry(this.typeName, this.version, this.toJson, this.fromJson);
}

///
/// Generate the json converter with this template:
/// ```
/// factory .fromJson(Map<String, dynamic> json) => _$FromJson(json);
/// Map<String, dynamic> toJson() => _$ToJson(this);
/// ```
///
/// see also [json_serializable](https://pub.dev/packages/json_serializable), [json_annotation](https://pub.dev/packages/json_annotation)
class JConverter {
  final Map<String, _ConvertibleProtocolEntry> _typeName2Entry = {};
  final Map<Type, _TypeEntry> _type2Entry = {};
  final Map<String, Migration> _migrations = {};
  JConverterKeys keys = _defaultConvertKeys;
  ConverterLoggerProtocol? logger;

  /// To add version into each json object for migration, which will significantly inflate the file size.
  bool enableMigration = false;
  late JsonCodec _jsonCodec;

  JConverter() {
    _jsonCodec = JsonCodec(reviver: _reviver, toEncodable: _toEncodable);
  }

  Object? _reviver(Object? key, Object? value) {
    if (value is Map) {
      final type = value[keys.type];
      if (type == null) {
        // It's a normal map, so return itself.
        return value;
      }
      final entry = _typeName2Entry[type];
      if (entry == null) {
        throw Exception("No FromJson for ${value.runtimeType} was found.");
      }
      if (enableMigration) {
        final version = value[keys.version];
        if (version is int) {
          final migration = _migrations[type];
          if (migration != null) {
            value = migration(value, version);
          }
        }
      }
      return entry.fromJson(value as Map<String, dynamic>);
    } else {
      return value;
    }
  }

  Object? _toEncodable(dynamic object) {
    if (object is JConvertibleProtocol) {
      final type = object.typeName;
      final entry = _typeName2Entry[type];
      if (entry == null) {
        throw Exception("No ToJson for ${object.typeName} was found.");
      }
      final toJsonFunc = entry.toJson;
      final Map<String, dynamic> json;
      if (toJsonFunc != null) {
        json = toJsonFunc(object);
      } else {
        json = (object as dynamic).toJson();
      }
      json[keys.type] = type;
      if (enableMigration) {
        json[keys.version] = object.version;
      }
      return json;
    } else {
      final entry = _type2Entry[object.runtimeType];
      if (entry != null) {
        final toJsonFunc = entry.toJson;
        final Map<String, dynamic> json;
        if (toJsonFunc != null) {
          json = toJsonFunc(object);
        } else {
          json = object.toJson();
        }
        json[keys.type] = entry.typeName;
        if (enableMigration) {
          json[keys.version] = entry.version;
        }
        return json;
      } else {
        return object;
      }
    }
  }

  void registerTypeAuto<T>(FromJsonFunc<T> fromJson, [String? typeName, int version = 1]) {
    typeName = typeName ?? T.toString();
    if (_type2Entry.containsKey(typeName)) {
      logger?.info("$typeName has been registered and will be override.");
    }
    _type2Entry[T] = _TypeEntry(typeName, version, null, fromJson);
  }

  void registerType<T>(FromJsonFunc<T> fromJson, ToJsonFunc? toJson, [String? typeName, int version = 1]) {
    typeName = typeName ?? T.toString();
    if (_type2Entry.containsKey(typeName)) {
      logger?.info("$typeName has been registered and will be override.");
    }
    _type2Entry[T] = _TypeEntry(typeName, version, toJson, fromJson);
  }

  void registerConvertible<T extends JConvertibleProtocol>(
      String typeName, FromJsonFunc<T> fromJson, ToJsonFunc? toJson) {
    if (_typeName2Entry.containsKey(typeName)) {
      logger?.info("$typeName has been registered and will be override.");
    }
    _typeName2Entry[typeName] = _ConvertibleProtocolEntry(toJson, fromJson);
  }

  void registerConvertibleAuto<T extends JConvertibleProtocol>(String typeName, FromJsonFunc<T> fromJson) {
    if (_typeName2Entry.containsKey(typeName)) {
      logger?.info("$typeName has been registered and will be override.");
    }
    _typeName2Entry[typeName] = _ConvertibleProtocolEntry(null, fromJson);
  }

  void registerMigration(String typeName, Migration migration) {
    if (enableMigration) {
      logger?.info("`enableMigration` is false now. Set it to true if migration is used later.");
    }
    _migrations[typeName] = migration;
  }

  String? toJson<T>(T obj, {int? indent}) {
    try {
      if (indent != null) {
        final encoder = JsonEncoder.withIndent(' ' * indent, _toEncodable);
        return encoder.convert(obj);
      } else {
        return _jsonCodec.encode(obj);
      }
    } on JsonUnsupportedObjectError catch (e) {
      logger?.error("Failed to convert $T to json", e.cause, e.stackTrace);
      return null;
    } catch (any, stacktrace) {
      logger?.error("Failed to convert $T to json", any, stacktrace);
      return null;
    }
  }

  /// If [T] is a collection, please use [List.cast], [Map.cast] or [Set.cast] to make a runtime-casting view.
  T? fromJson<T>(String? json) {
    if (json == null) return null;
    try {
      return _jsonCodec.decode(json) as T?;
    } on JsonUnsupportedObjectError catch (e) {
      logger?.error("Failed to convert json to $T", e.cause, e.stackTrace);
      return null;
    } catch (any, stacktrace) {
      logger?.error("Failed to convert json to $T", any, stacktrace);
      return null;
    }
  }

  T? fromUntypedJson<T>(String? json, T Function(Map<String, dynamic> json) fromJson) {
    if (json == null) return null;
    try {
      final jObj = jsonDecode(json);
      return fromJson(jObj);
    } on JsonUnsupportedObjectError catch (e) {
      logger?.error("Failed to convert json to $T", e.cause, e.stackTrace);
      return null;
    } catch (any, stacktrace) {
      logger?.error("Failed to convert json to $T", any, stacktrace);
      return null;
    }
  }

  String? toUntypedJson<T>(T? obj, {Map<String, dynamic> Function(T obj)? toJson, int? indent}) {
    if (obj == null) return null;
    try {
      final jObj = toJson != null ? toJson(obj) : obj;
      if (indent != null) {
        final encoder = JsonEncoder.withIndent(' ' * indent);
        return encoder.convert(obj);
      } else {
        return jsonEncode(jObj);
      }
    } on JsonUnsupportedObjectError catch (e) {
      logger?.error("Failed to convert $T to json", e.cause, e.stackTrace);
      return null;
    } catch (any, stacktrace) {
      logger?.error("Failed to convert $T to json", any, stacktrace);
      return null;
    }
  }
}
