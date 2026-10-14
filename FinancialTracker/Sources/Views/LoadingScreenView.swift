//
//  LoadingScreenView.swift
//  Worthly
//

import SwiftUI

public struct LoadingScreenView: View {
    @AppStorage("app_language") private var appLanguage: String = "en"
    
    @State private var iconScale: CGFloat = 0.82
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var progressAmount: Double = 0.15
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Adaptive background for Dark / Light mode
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // Branded App Icon Badge
                ZStack {
                    // Soft ambient gradient halo
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.blue.opacity(0.22), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 85
                            )
                        )
                        .frame(width: 170, height: 170)
                    
                    // Rounded app icon tile
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#007AFF"), Color(hex: "#5856D6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.blue.opacity(0.32), radius: 18, x: 0, y: 8)
                    
                    // Foreground symbol
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                
                // Title and Subtitle
                VStack(spacing: 8) {
                    Text(L10n.tr("Worthly", lang: appLanguage))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(L10n.tr("Private • Fast • On-Device", lang: appLanguage))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .opacity(textOpacity)
                
                Spacer()
                
                // Bottom Loading Progress Indicator
                VStack(spacing: 12) {
                    ProgressView(value: progressAmount, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(width: 160)
                    
                    Text(L10n.tr("Loading your finances...", lang: appLanguage))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.bottom, 48)
                .opacity(textOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.18)) {
                textOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 0.8).delay(0.1)) {
                progressAmount = 1.0
            }
        }
    }
}
