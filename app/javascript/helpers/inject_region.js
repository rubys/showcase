// Helper function to inject Fly.io region/machine headers for request routing
// This must be loaded eagerly (not lazy) since it's used by multiple controllers
// that may load before the region controller is instantiated

window.inject_region = function(headers) {
  if (document.body.dataset.machine) {
    return Object.assign({}, headers, {'Fly-Prefer-Instance-Id': document.body.dataset.machine})
  } else if (document.body.dataset.region) {
    return Object.assign({}, headers, {'Fly-Prefer-Region': document.body.dataset.region})
  } else {
    return headers
  }
}
