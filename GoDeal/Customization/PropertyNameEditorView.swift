import SwiftUI

// MARK: - Property Name Editor View
// Lets users rename street names per district.

struct PropertyNameEditorView: View {
    @Environment(CustomizationViewModel.self) private var viewModel
    @State private var selectedColor: PropertyColor = .rustDistrict
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(PropertyColor.allCases, id: \.self) { color in
                    Section {
                        ForEach(viewModel.editingNames[color]?.indices ?? 0..<0, id: \.self) { index in
                            HStack {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                TextField(
                                    color.defaultStreetNames[safe: index] ?? "",
                                    text: Binding(
                                        get: { viewModel.editingNames[color]?[index] ?? "" },
                                        set: { viewModel.updateName($0, for: color, at: index) }
                                    )
                                )
                                .textInputAutocapitalization(.words)
                            }
                        }

                        Button("Reset \(color.displayName) to defaults") {
                            viewModel.resetNames(for: color)
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    } header: {
                        HStack {
                            Circle()
                                .fill(color.uiColor)
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                        }
                    }
                }
            }
            .navigationTitle("Edit Street Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save All") {
                        viewModel.saveAllNames()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.hasUnsavedChanges)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset All", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
            .confirmationDialog(
                "Reset all street names to defaults?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset All", role: .destructive) {
                    viewModel.resetAllNames()
                }
            }
        }
    }
}

// MARK: - Color Extension
extension PropertyColor {
    var uiColor: Color {
        switch self {
        case .rustDistrict:   return Color(red: 0.6, green: 0.3, blue: 0.1)
        case .skylineAve:     return Color.cyan.opacity(0.8)
        case .neonRow:        return Color(red: 0.9, green: 0.4, blue: 0.7)
        case .sunsetStrip:    return Color.orange
        case .hotZone:        return Color.red
        case .goldRush:       return Color.yellow
        case .emeraldQuarter: return Color.green
        case .blueChip:       return Color.blue
        case .transitLine:    return Color(red: 0.2, green: 0.2, blue: 0.2)
        case .powerAndWater:  return Color(red: 0.7, green: 0.7, blue: 0.3)
        }
    }
}

#Preview {
    PropertyNameEditorView()
        .environment(CustomizationViewModel())
}
