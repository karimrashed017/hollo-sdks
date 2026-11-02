// Expo config plugin. The SDK is pure JavaScript today, so there's nothing
// to change in the native projects; the plugin exists so app.json's
// "plugins": ["@hollo/react-native"] keeps working when native push lands.
module.exports = function withHollo(config) {
  return config;
};
