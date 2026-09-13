import Foundation

enum AppRoute: Hashable {
    case home
    case productHub
    case profile(String)
    case post(String)
    case product(String)
    case module(String)
    case account
    case settings
}
