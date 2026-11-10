import Darwin
import SwiftUI

@main enum ApplicationEntry {
    static func main() {
        if let result = FeatureToolValidation.runIfRequested() { exit(result) }
        AutoProductiveApp.main()
    }
}
