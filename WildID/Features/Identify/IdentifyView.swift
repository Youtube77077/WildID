import SwiftUI
import SwiftData

struct IdentifyView: View {
    @Environment(Router.self) private var router
    @Environment(SoundIDSession.self) private var sound
    @Query(sort: \SavedRecording.startedAt, order: .reverse) private var recordings: [SavedRecording]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Identify").font(.wildLargeTitle).padding(.top, 8)
                    Text("Three ways to put a name to an animal.")
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)

                    Button { router.showSoundID = true } label: {
                        IdentifyCard(symbol: "mic.fill", title: "Sound ID",
                                     subtitle: BirdNETClassifier.isAvailable
                                        ? "Listen live and name the animals singing around you — 6,500+ species of birds plus frogs, insects and mammals, and everyday animal sounds."
                                        : "Listen live for animal sounds. The species model is missing from this build — see README.",
                                     prominent: true, badge: sound.isActive ? "Listening…" : nil)
                    }
                    .buttonStyle(PressableStyle())

                    Button { router.showPhotoID = true } label: {
                        IdentifyCard(symbol: "camera.fill", title: "Photo ID",
                                     subtitle: "Take or choose a photo. WildID recognises the kind of animal on-device, then shows the matching species recorded near you to compare.")
                    }
                    .buttonStyle(PressableStyle())

                    Button { router.showGuidedID = true } label: {
                        IdentifyCard(symbol: "list.bullet.clipboard", title: "Step by Step",
                                     subtitle: "No photo or sound? Answer a few questions about what you saw and where.")
                    }
                    .buttonStyle(PressableStyle())

                    Button { router.showRecordings = true } label: {
                        HStack {
                            Image(systemName: "waveform")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sound ID Sessions").font(.headline)
                                Text(recordings.isEmpty ? "Saved recordings appear here"
                                     : "\(recordings.count) saved • \(FileStore.formatted(recordings.reduce(0) { $0 + $1.fileSize }))")
                                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.tertiaryText)
                        }
                        .foregroundStyle(.primary)
                        .wildCard()
                    }
                    .buttonStyle(PressableStyle())

                    Label("Identification uses real reference data: BirdNET (trained on Xeno-canto & Macaulay Library recordings), Apple's on-device sound and image recognition, and iNaturalist observations. Results are suggestions — always check the species page.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 6)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct IdentifyCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    var prominent = false
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(prominent ? AnyShapeStyle(Theme.moss.gradient) : AnyShapeStyle(Theme.softFill))
                .frame(width: 60, height: 60)
                .overlay(Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(prominent ? .white : .primary.opacity(0.7)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.system(size: 20, weight: .bold))
                    if let badge { Pill(text: badge, symbol: "dot.radiowaves.left.and.right", tint: Theme.ember) }
                }
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .wildCard(padding: 18)
    }
}
