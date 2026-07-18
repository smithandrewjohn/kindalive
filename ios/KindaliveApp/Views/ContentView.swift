// ContentView — the dashboard, mirroring docs/web-ui.md collapsed to a
// phone-first single column: header, LED face with mood caption, reply
// bubble, status line, input bar, then the chemistry/emotion bar panels.
// On regular width (iPad / landscape) the bar panels flank the face,
// reproducing the web UI's three-column layout.

import KindaliveKit
import SwiftUI

struct ContentView: View {
    @State private var model = RobotViewModel()
    @State private var draft = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(model: model)
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    ChemicalBarsView(model: model)
                        .frame(maxWidth: 260)
                    centerColumn
                    EmotionBarsView(model: model)
                        .frame(maxWidth: 260)
                }
                .padding(.horizontal)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        centerColumn
                        ChemicalBarsView(model: model)
                        EmotionBarsView(model: model)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                model.save()
            }
        }
    }

    private var centerColumn: some View {
        VStack(spacing: 10) {
            FaceMatrixView(model: model.faceModel)

            let dominant = model.dominantEmotion
            Text("\(dominant.name) \(dominant.value, specifier: "%.2f")")
                .font(.headline.monospaced())
                .foregroundStyle(Color(hex: model.moodColorHex))

            Text(model.topEmotions
                .map { "\($0.name) \(String(format: "%.2f", $0.value))" }
                .joined(separator: " · "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            ReplyBubbleView(reply: model.lastReply)
            StatusLineView(model: model)
            InputBarView(model: model, draft: $draft)
        }
        .padding(.vertical, 8)
    }
}

struct HeaderBar: View {
    let model: RobotViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("KINDALIVE")
                .font(.headline.monospaced().weight(.heavy))
                .foregroundStyle(Color(hex: model.moodColorHex))

            Menu {
                ForEach(personalityNames, id: \.self) { name in
                    Button(name) { model.setPersonality(name) }
                }
            } label: {
                Label(model.personality, systemImage: "person.crop.circle")
                    .font(.caption)
            }

            Picker("Speed", selection: Binding(
                get: { model.speed },
                set: { model.speed = $0 }
            )) {
                ForEach(speedOptions) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)

            Spacer()

            Button {
                model.voiceOn.toggle()
            } label: {
                Image(systemName: model.voiceOn ? "speaker.wave.2.fill" : "speaker.slash")
            }

            Button("Reset") { model.reset() }
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Text(model.modelStatus)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing)
                .offset(y: 8)
        }
    }
}

struct ReplyBubbleView: View {
    let reply: String

    var body: some View {
        if !reply.isEmpty {
            Text("🗣 \(reply)")
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .transition(.opacity)
        }
    }
}

struct StatusLineView: View {
    let model: RobotViewModel

    var body: some View {
        if !model.statusLine.isEmpty {
            Text(model.statusLine)
                .font(.caption2.monospaced())
                .foregroundStyle(
                    model.statusLine.contains("FALLBACK") ? .orange : .secondary
                )
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InputBarView: View {
    let model: RobotViewModel
    @Binding var draft: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "Tell the robot what's happening…",
                text: $draft,
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit(send)

            Button(action: send) {
                if model.isProcessing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(model.isProcessing
                || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await model.send(text) }
    }
}

extension Color {
    /// "#rrggbb" → Color (mood accents from MoodPalette).
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        let value = UInt32(cleaned, radix: 16) ?? 0x4FB7A6
        self.init(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }
}
