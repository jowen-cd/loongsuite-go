// Test hooks normally injected into the user's OTel SDK by file rules.
// The fork carries them natively; see pkg/testaccess.
package metric

var GetTestMetrics func() (interface{}, error)
