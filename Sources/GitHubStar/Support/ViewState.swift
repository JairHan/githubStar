import SwiftUI

// Use the property-wrapper type explicitly: recent SDKs also export a State macro
// whose plugin is not bundled with standalone Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
