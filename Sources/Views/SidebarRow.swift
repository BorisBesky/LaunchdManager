import SwiftUI

/// A sidebar category row implemented as a plain button.
/// List-based selection proved unreliable here (no highlight, no filter),
/// so selection is handled explicitly.
struct SidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(count, format: .number)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
