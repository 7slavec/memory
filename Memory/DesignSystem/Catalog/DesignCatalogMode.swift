import Foundation

enum DesignCatalogMode {
    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--design-catalog")
#else
        false
#endif
    }
}
