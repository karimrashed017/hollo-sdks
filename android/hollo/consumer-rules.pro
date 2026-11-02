# Hollo uses no reflection: JSON is read through kotlinx.serialization's
# JsonElement API (no generated serializers), and the chat activity is kept
# because the library manifest declares it.

# Firebase is compile-only (for Hollo.handle(RemoteMessage)). Apps that don't
# use Firebase never call that method, so R8 mustn't fail on the missing class.
-dontwarn com.google.firebase.messaging.RemoteMessage
