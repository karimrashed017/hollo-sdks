import 'package:shared_preferences/shared_preferences.dart';

/// Where the SDK keeps this install's device token and a few small flags.
/// Pass your own to `Hollo.start(storage: ...)` to use, say, secure storage.
abstract class HolloStorage {
  Future<String?> getItem(String key);
  Future<void> setItem(String key, String value);
  Future<void> removeItem(String key);
}

/// The default: shared_preferences, so the token survives app restarts.
class SharedPreferencesHolloStorage implements HolloStorage {
  const SharedPreferencesHolloStorage();

  @override
  Future<String?> getItem(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> setItem(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  @override
  Future<void> removeItem(String key) async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}
