// Test hooks normally injected into the user's OTel SDK by file rules.
// The fork carries them natively; see pkg/testaccess.
package trace

var GetTestSpans func() interface{}
var ResetTestSpans func()
