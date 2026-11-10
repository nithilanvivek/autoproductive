import Combine
import Foundation

struct AppNavigationRequest {
    let id = UUID()
    let route: AppRoute?
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published private(set) var request: AppNavigationRequest?

    func open(_ route: AppRoute? = nil) {
        request = AppNavigationRequest(route: route)
    }
}
