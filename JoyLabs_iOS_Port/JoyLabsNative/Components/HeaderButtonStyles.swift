import SwiftUI

// MARK: - Header Button Styling System
/// Centralized styling for header buttons with iOS 26 glass effects
/// Provides consistent, round, glass-effect buttons for headers

// MARK: - Header Button Style
struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .frame(width: ItemDetailsSpacing.minimumTouchTarget, height: ItemDetailsSpacing.minimumTouchTarget)
            .background(.clear)
            .clipShape(Circle())
            .glassEffect()
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Convenience Extension
extension ButtonStyle where Self == HeaderButtonStyle {
    static var headerButton: HeaderButtonStyle {
        HeaderButtonStyle()
    }
}

// MARK: - Header Button Component
/// Standardized header button with consistent styling
struct HeaderButton<Content: View>: View {
    let action: () -> Void
    let content: Content

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.headerButton)
    }
}

// MARK: - Icon Header Button
/// Standard header button with just an icon
struct IconHeaderButton: View {
    let icon: String
    let action: () -> Void

    init(_ icon: String, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    var body: some View {
        HeaderButton(action: action) {
            Image(systemName: icon)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Badge Header Button
/// Header button with optional badge (for notifications, counts)
struct BadgeHeaderButton: View {
    let icon: String
    let badgeCount: Int
    let action: () -> Void

    init(_ icon: String, badgeCount: Int = 0, action: @escaping () -> Void) {
        self.icon = icon
        self.badgeCount = badgeCount
        self.action = action
    }

    var body: some View {
        HeaderButton(action: action) {
            ZStack {
                Image(systemName: icon)
                    .foregroundColor(.primary)

                // Badge for count
                if badgeCount > 0 {
                    Text("\(badgeCount > 99 ? "99+" : "\(badgeCount)")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, badgeCount > 9 ? 4 : 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(1.0))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
}

// MARK: - Menu Header Button
/// Header button that triggers a menu
struct MenuHeaderButton<MenuContent: View>: View {
    let icon: String
    let menuContent: MenuContent

    init(_ icon: String, @ViewBuilder menuContent: () -> MenuContent) {
        self.icon = icon
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: icon)
                .foregroundColor(.primary)
        }
        .buttonStyle(.headerButton)
    }
}