import SwiftUI

/// Bottom card that names the sampled color. Large, high-contrast text —
/// this is the whole point of the app for the user.
struct ColorReadoutView: View {
    let match: ColorMatcher.Match?
    let sampledColor: Color
    var mode: Analytics.ReadingMode = .live
    var isFrozen: Bool = false
    var onToggleFreeze: (() -> Void)?
    @State private var correctedColor: NamedColor?
    @State private var showCorrectionPicker = false
    @AppStorage("isDiagnosticModeEnabled") private var isDiagnosticModeEnabled = false
    @AppStorage("redGain") private var redGain: Double = 1.0
    @AppStorage("greenGain") private var greenGain: Double = 1.0
    @AppStorage("blueGain") private var blueGain: Double = 1.0

    var body: some View {
        HStack(spacing: 14) {
            swatch

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryLabel)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                HStack(spacing: 8) {
                    if let match {
                        Text(secondaryLabel(for: match))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Aim the crosshair at something")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 8) {
                if isDiagnosticModeEnabled {
                    Text("DIAG")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .overlay(Capsule().strokeBorder(.orange.opacity(0.4), lineWidth: 1))
                }

                if let onToggleFreeze {
                    Button {
                        onToggleFreeze()
                    } label: {
                        Image(systemName: isFrozen ? "play.fill" : "pause.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(isFrozen ? .blue.opacity(0.25) : .white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(Text(isFrozen ? "Resume" : "Freeze"))
                }

                if match != nil {
                    Button {
                        showCorrectionPicker = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(Text("Correct color"))
                }
            }
            .padding(.trailing, 10)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { }
        .onChange(of: matchIdentity) { _, _ in
            correctedColor = nil
        }
        .sheet(isPresented: $showCorrectionPicker) {
            ColorCorrectionPickerView(
                selectedColorName: correctedColor?.name,
                onSelect: { selected in
                    if let fromName = currentDisplayedName, fromName != selected.name {
                        Analytics.signal(
                            Analytics.Event.readingCorrected,
                            parameters: correctionParameters(from: fromName, to: selected.name)
                        )
                    }
                    correctedColor = selected
                },
                onReset: {
                    if let fromColor = correctedColor, let detected = match?.name {
                        Analytics.signal(
                            Analytics.Event.readingCorrectionCleared,
                            parameters: correctionParameters(from: fromColor.name, to: detected)
                        )
                    }
                    correctedColor = nil
                }
            )
        }
    }

    /// Builds the privacy-safe parameter dict for correction signals.
    /// Includes `mode`, `calibrated`, and a coarse `hueBucket` of the
    /// sampled color so the TelemetryDeck dashboard can slice corrections
    /// by surface, calibration state, and hue family.
    private func correctionParameters(from fromName: String, to toName: String) -> [String: String] {
        let comps = colorComponents
        return [
            "from": fromName,
            "to": toName,
            "mode": mode.rawValue,
            "calibrated": isCalibrated ? "true" : "false",
            "hueBucket": Analytics.hueBucket(red: comps.r, green: comps.g, blue: comps.b)
        ]
    }

    private var isCalibrated: Bool {
        abs(redGain - 1.0) > 0.01 || abs(greenGain - 1.0) > 0.01 || abs(blueGain - 1.0) > 0.01
    }

    private var primaryLabel: String {
        guard let displayed = displayedMatch else { return String(localized: "Point at a color") }
        if let correctedColor {
            return correctedColor.name
        }
        if let alt = displayed.alternateName, isAmbiguous(displayed) {
            return "\(displayed.name) / \(alt)"
        }
        return displayed.name
    }

    private func secondaryLabel(for match: ColorMatcher.Match) -> String {
        if correctedColor != nil {
            return "Corrected"
        }
        if isDiagnosticModeEnabled {
            // Show RGB values in diagnostic mode
            let r = Int(colorComponents.r * 255)
            let g = Int(colorComponents.g * 255)
            let b = Int(colorComponents.b * 255)
            return "R:\(r)  G:\(g)  B:\(b)"
        }
        if match.alternateName != nil && isAmbiguous(match) {
            return "Uncertain match"
        }
        return ""
    }

    private func isAmbiguous(_ match: ColorMatcher.Match) -> Bool {
        match.confidence < 0.5
    }

    private var colorComponents: (r: Double, g: Double, b: Double) {
        // Extract RGB from Color using UIColor on iOS
        #if os(iOS)
        let uiColor = UIColor(sampledColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        return (0, 0, 0)
        #endif
    }

    private var displayedMatch: ColorMatcher.Match? {
        if let correctedColor {
            return ColorMatcher.Match(
                name: correctedColor.name,
                composition: correctedColor.composition,
                alternateName: nil,
                confidence: 1
            )
        }
        return match
    }

    private var matchIdentity: String {
        guard let match else { return "none" }
        return "\(match.name)|\(match.composition)"
    }

    private var currentDisplayedName: String? {
        if let correctedColor { return correctedColor.name }
        return match?.name
    }

    @ViewBuilder
    private var swatch: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(displayedMatch == nil ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(sampledColor))
            .frame(width: 44, height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(displayedMatch == nil ? 0.25 : 0.4), lineWidth: 1)
            }
            .overlay {
                if displayedMatch == nil {
                    Image(systemName: "scope")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
    }
}

private struct ColorCorrectionPickerView: View {
    let selectedColorName: String?
    let onSelect: (NamedColor) -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if selectedColorName != nil {
                    Button("Use detected color") {
                        onReset()
                        dismiss()
                    }
                }
                ForEach(NamedColor.palette, id: \.name) { candidate in
                    Button {
                        onSelect(candidate)
                        dismiss()
                    } label: {
                        HStack {
                            Circle()
                                .fill(candidate.color)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                            Text(candidate.name)
                            Spacer()
                            if selectedColorName == candidate.name {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Correct color")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ColorCalibrationView: View {
    @Binding var redGain: Double
    @Binding var greenGain: Double
    @Binding var blueGain: Double
    let currentRed: Double
    let currentGreen: Double
    let currentBlue: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Point at something white or neutral gray, then tap Calibrate to baseline the colors.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Current reading swatch
                VStack(spacing: 8) {
                    Text("Current Reading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.sRGB, red: currentRed, green: currentGreen, blue: currentBlue, opacity: 1))
                        .frame(width: 80, height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))

                    Text("R: \(Int(currentRed * 255)) G: \(Int(currentGreen * 255)) B: \(Int(currentBlue * 255))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Current gains
                VStack(spacing: 12) {
                    Text("Calibration Gains")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        gainLabel("R", value: redGain, color: .red)
                        gainLabel("G", value: greenGain, color: .green)
                        gainLabel("B", value: blueGain, color: .blue)
                    }
                }

                Spacer()

                Button("Calibrate to White") {
                    // Calculate gains so current reading becomes ~0.9 (near white but not clipped)
                    let target: Double = 0.9
                    if currentRed > 0.01 { redGain = target / currentRed }
                    if currentGreen > 0.01 { greenGain = target / currentGreen }
                    if currentBlue > 0.01 { blueGain = target / currentBlue }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Reset to Default") {
                    redGain = 1.0
                    greenGain = 1.0
                    blueGain = 1.0
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding()
            .navigationTitle("Color Calibration")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func gainLabel(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(String(format: "%.2f", value))
                .font(.caption.monospaced())
        }
    }
}

// MARK: - Complementary Colors

/// Expandable strip below the color readout showing complementary color
/// suggestions. Tapping the chevron toggles between collapsed (just a hint
/// label) and expanded (swatches with names).
struct ComplementaryColorsView: View {
    let suggestions: [ColorHarmony.Suggestion]
    @State private var isExpanded = false

    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                // Toggle button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                    if isExpanded {
                        Analytics.signal(Analytics.Event.complementaryExpanded)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Goes well with")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                // Expanded content
                if isExpanded {
                    HStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { }
        }
    }

    private func suggestionCard(_ suggestion: ColorHarmony.Suggestion) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(suggestion.namedColor.color)
                .frame(height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }

            Text(suggestion.namedColor.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
