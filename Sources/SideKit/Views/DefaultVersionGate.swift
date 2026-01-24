//
//  DefaultVersionGate.swift
//  SideKit
//
//  Created by Ashish Selvaraj on 2025-11-24.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct DefaultVersionGate: View {
    @Environment(\.dismiss) private var dismiss
    private let dismissible: Bool
    private let onSkip: (() -> Void)?
    
    @ObservedObject private var sideKit = SideKit.shared
    
    public init(dismissible: Bool = true, onSkip: (() -> Void)? = nil) {
        self.dismissible = dismissible
        self.onSkip = onSkip
    }
    
    private var version: String? {
        sideKit.gateInformation?.latestVersion
    }
    
    private var updateDescription: String? {
        sideKit.gateInformation?.whatsNew
    }
    
    public var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.0, green: 0.0, blue: 0.0),
                    .blue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 100)
                
                // Title
                VStack(alignment: .leading, spacing: -12) {
                    Text("Update")
                    Text("Available")
                }
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 40)
                
                // Version and Description (Inline)
                #if canImport(UIKit)
                if let version = version, let badgeImage = renderBadge(for: version) {
                    (Text(Image(uiImage: badgeImage))
                        .baselineOffset(-5) // Center the taller badge with the text
                     + Text("  ") // Spacing
                     + Text(updateDescription ?? "")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.95)))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                } else if let version = version {
                    // Fallback: just show version text if badge rendering fails
                    Text("\(version)  \(updateDescription ?? "")")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #else
                if let version = version {
                    Text("\(version)  \(updateDescription ?? "")")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.95))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif
                
                Spacer()
                
                // Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        if let storeUrlString = sideKit.gateInformation?.storeUrl,
                           let url = URL(string: storeUrlString) {
                            openURL(url)
                        }
                    }) {
                        Text("Get the Update")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.white)
                            .cornerRadius(18)
                    }
                    
                    if dismissible {
                        Button(action: {
                            onSkip?()
                            dismiss()
                        }) {
                            Text("Skip for now")
                                .font(.callout)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color.white, lineWidth: 3)
                                )
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 30)
        }
    }
    
    #if canImport(UIKit)
    private func renderBadge(for versionText: String) -> UIImage? {
        let label = UILabel()
        label.text = versionText
        label.font = .systemFont(ofSize: 13, weight: .heavy)
        label.textColor = .black
        label.backgroundColor = .white
        label.textAlignment = .center
        
        // Calculate size with padding
        let padding = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        let size = label.intrinsicContentSize
        let finalSize = CGSize(width: size.width + padding.left + padding.right, height: size.height + padding.top + padding.bottom)
        
        label.frame = CGRect(origin: .zero, size: finalSize)
        label.layer.cornerRadius = finalSize.height > 0 ? finalSize.height / 2 : 0
        label.layer.masksToBounds = true
        
        UIGraphicsBeginImageContextWithOptions(finalSize, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        label.layer.render(in: context)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    #endif
    
    private func openURL(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}

#Preview {
    DefaultVersionGate(dismissible: true)
}
