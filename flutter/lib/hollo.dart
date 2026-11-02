/// Hollo in-app support chat for Flutter apps.
///
/// ```dart
/// await Hollo.start(appKey: 'app_XXXX');
/// runApp(MaterialApp(navigatorKey: Hollo.navigatorKey, home: const Home()));
/// // Later, from a Support button:
/// Hollo.present();
/// ```
library;

export 'src/client.dart' show HolloError;
export 'src/hollo.dart' show Hollo, HolloChat;
export 'src/models.dart'
    show
        HolloLink,
        HolloMessage,
        HolloOffer,
        HolloPermissionCard,
        HolloProfile,
        HolloPushSettings;
export 'src/storage.dart' show HolloStorage, SharedPreferencesHolloStorage;
export 'src/ui.dart' show HolloTheme;
