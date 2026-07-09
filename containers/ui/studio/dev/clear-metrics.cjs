// Workaround for prom-client double-registration with bun's module resolution.
// Clears the default metrics registry before the app starts.
try {
  require('prom-client').register.clear()
} catch (e) {
  // prom-client not available yet, that's fine
}
