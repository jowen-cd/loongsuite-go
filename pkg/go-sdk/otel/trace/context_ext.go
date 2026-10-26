// Exported alias of the unexported context key, used by the
// rules/otsdk bridge to mirror the fork's current span into
// user OTel contexts.
package trace

const CurrentSpanKey = currentSpanKey
