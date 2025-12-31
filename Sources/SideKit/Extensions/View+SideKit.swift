import SwiftUI

public struct SideKitUpdateGateModifier: ViewModifier {
    @ObservedObject private var sideKit = SideKit.shared
    
    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .fullScreenCover(isPresented: $sideKit.showUpdateScreen) {
                DefaultVersionGate(onSkip: {
                    sideKit.showUpdateScreen = false
                })
            }
        #elseif os(macOS)
        content
            .sheet(isPresented: $sideKit.showUpdateScreen) {
                DefaultVersionGate(onSkip: {
                    sideKit.showUpdateScreen = false
                })
            }
        #else
        content
        #endif
    }
}

public extension View {
    /// Monitors SideKit's version status and automatically presents the update gate as a full-screen cover.
    func sideKitUpdateGate() -> some View {
        self.modifier(SideKitUpdateGateModifier())
    }
}
