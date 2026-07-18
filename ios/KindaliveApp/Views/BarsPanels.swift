// Chemistry / emotion bar panels — the two live-value panels from the
// web UI, using the shared MoodPalette colors.

import KindaliveKit
import SwiftUI

struct ChemicalBarsView: View {
    let model: RobotViewModel

    var body: some View {
        BarsPanel(
            title: "Neurochemistry",
            rows: Chemical.allCases.map { chem in
                BarRowData(
                    name: chem.rawValue,
                    value: model.chemicalLevels[chem] ?? 0,
                    colorHex: MoodPalette.chemicalColors[chem] ?? MoodPalette.defaultMoodColor
                )
            }
        )
    }
}

struct EmotionBarsView: View {
    let model: RobotViewModel

    var body: some View {
        BarsPanel(
            title: "Emotion mix",
            rows: model.emotions.orderedValues.map { entry in
                BarRowData(
                    name: entry.name,
                    value: entry.value,
                    colorHex: MoodPalette.emotionColors[entry.name] ?? MoodPalette.defaultMoodColor
                )
            }
        )
    }
}

struct BarRowData: Identifiable {
    let name: String
    let value: Double
    let colorHex: String
    var id: String { name }
}

struct BarsPanel: View {
    let title: String
    let rows: [BarRowData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 92, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.07))
                            Capsule()
                                .fill(Color(hex: row.colorHex))
                                .frame(width: max(3, geo.size.width * row.value))
                        }
                    }
                    .frame(height: 7)
                    Text(String(format: "%.2f", row.value))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}
