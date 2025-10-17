/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Extensions and supporting SwiftUI types.
*/

import SwiftUI
import UIKit

let largeButtonSize = CGSize(width: 64, height: 64)
let smallButtonSize = CGSize(width: 32, height: 32)

@MainActor
protocol PlatformView: View {
    var verticalSizeClass: UserInterfaceSizeClass? { get }
    var horizontalSizeClass: UserInterfaceSizeClass? { get }
    var isRegularSize: Bool { get }
    var isCompactSize: Bool { get }
}

extension PlatformView {
    var isRegularSize: Bool { horizontalSizeClass == .regular && verticalSizeClass == .regular }
    var isCompactSize: Bool { horizontalSizeClass == .compact || verticalSizeClass == .compact }
}

/// A container view for the app's toolbars that lays the items out horizontally
/// on iPhone and vertically on iPad and Mac Catalyst.
struct AdaptiveToolbar<Content: View>: PlatformView {
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private let horizontalSpacing: CGFloat
    private let verticalSpacing: CGFloat
    private let content: Content
    
    init(horizontalSpacing: CGFloat = 0.0, verticalSpacing: CGFloat = 0.0, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }
    
    var body: some View {
        if isRegularSize {
            VStack(spacing: verticalSpacing) { content }
        } else {
            HStack(spacing: horizontalSpacing) { content }
        }
    }
}

struct DefaultButtonStyle: ButtonStyle {
    
    @Environment(\.isEnabled) private var isEnabled: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum Size: CGFloat {
        case small = 22
        case large = 24
    }
    
    private let size: Size
    
    init(size: Size) {
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? .white : Color(white: 0.4))
            .font(.system(size: size.rawValue))
            // Pad buttons on devices that use the `regular` size class,
            // and also when explicitly requesting large buttons.
            .padding(isRegularSize || size == .large ? 10.0 : 0)
            // Apply Liquid Glass effect (iOS 26 placeholder using Material)
            .glassEffect(.regular, in: size == .small ? .rect(cornerRadius: 0) : .circle)
    }
    
    var isRegularSize: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

extension View {
    func debugBorder(color: Color = .red) -> some View {
        self
            .border(color)
    }
}

extension Image {
    init(_ image: CGImage) {
        self.init(uiImage: UIImage(cgImage: image))
    }
}

// MARK: - Glass Effect (iOS 18+ Material-Based)

extension View {
    /// Applies a glass-like visual effect to the view using iOS 18+ Material effects
    ///
    /// This implementation uses the Material API available in iOS 18+ to create
    /// a glass-like appearance with blur, transparency, and subtle borders.
    ///
    /// - Parameters:
    ///   - variant: The glass effect variant (regular, clear, or identity)
    ///   - shape: The shape to apply the effect within
    /// - Returns: A view with glass-like visual effects
    func glassEffect(_ variant: GlassEffectVariant = .regular, in shape: GlassEffectShape) -> some View {
        let material: Material = {
            switch variant {
            case .regular:
                return .ultraThinMaterial
            case .clear:
                return .thin
            case .identity:
                return .regular
            }
        }()

        let opacity: Double = {
            switch variant {
            case .regular:
                return 0.8
            case .clear:
                return 0.6
            case .identity:
                return 1.0
            }
        }()

        return self
            .background(material.opacity(opacity))
            .clipShape(shapeForEffect(shape))
            .overlay(
                shapeForEffect(shape)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }

    private func shapeForEffect(_ shape: GlassEffectShape) -> AnyShape {
        switch shape {
        case .circle:
            return AnyShape(Circle())
        case .capsule:
            return AnyShape(Capsule())
        case .rect(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius))
        }
    }
}

/// Glass effect shape variants
enum GlassEffectShape {
    case circle
    case capsule
    case rect(cornerRadius: CGFloat)
}

/// Glass effect variants
enum GlassEffectVariant {
    /// Regular glass effect with standard blur and transparency
    case regular
    /// Clear glass effect with less blur and more transparency
    case clear
    /// Identity glass effect with minimal blur
    case identity
}

/// A type-erased shape
struct AnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        _path = { rect in
            shape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}
