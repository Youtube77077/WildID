import SwiftUI

/// Live Sound ID: scrolling spectrogram, detections appearing as they happen, record controls.
struct SoundIDView: View {
    @Environment(SoundIDSession.self) private var sound
    @Environment(Router.self) private var router
    @Environment(LocationService.self) private var location
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    @State private var confirmStop = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if sound.state == .finished, sound.summary != nil {
                    SessionSummaryView(onDone: { router.showSoundID = false })
                } else {
                    live
                }
            }
            .wildDestinations()
        }
        // Small, non-blocking pop-up above the record controls; recording continues.
        .newAnimalToasts(bottomPadding: 118) { species in path.append(species) }
        .task {
            if sound.state == .idle { await sound.start() }
        }
    }

    private var live: some View {
        VStack(spacing: 0) {
            LiveSpectrogramView(processor: sound.spectrogram, isActive: scenePhase == .active && sound.state == .recording)
                .frame(height: 150)
                .overlay(alignment: .bottomLeading) { frequencyScale }
            contextStrip
            if let message = sound.statusMessage ?? sound.modelError {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            detectionsList
            controls
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.showSoundID = false
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Minimise — keep listening")
            }
            ToolbarItem(placement: .principal) {
                Text(sound.state == .paused ? "Paused" : sound.state == .starting ? "Starting…" : "Sound ID")
                    .font(.headline)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var frequencyScale: some View {
        VStack(alignment: .leading) {
            Text("12 kHz"); Spacer(); Text("6"); Spacer(); Text("0")
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.secondaryText.opacity(0.8))
        .padding(.vertical, 4)
        .padding(.leading, 6)
        .frame(height: 150)
        .allowsHitTesting(false)
    }

    private var contextStrip: some View {
        HStack {
            if let expected = sound.expectedSpeciesCount {
                Label("\(expected) species expected here this week", systemImage: "location.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text("\(Date().formatted(.dateTime.month(.wide).day())) - \(sound.placeName ?? location.activePlace?.name ?? "Locating…")")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
        .background(Theme.lichen.opacity(0.5))
    }

    private var detectionsList: some View {
        Group {
            if sound.detections.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(sound.state == .paused ? "Paused" : "Listening for animals")
                        .font(.system(size: 26, weight: .bold))
                    Text("near \(sound.placeName ?? location.activePlace?.name ?? "you")")
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)
                    if location.activePlace == nil {
                        Text("Turn on location so WildID can rule out animals that don't live here.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sound.detections) { d in
                            NavigationLink(value: d.species) {
                                DetectionCard(detection: d, elapsed: sound.elapsed, now: sound.clock,
                                              showScientific: settings.showScientificNames)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 100)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        ZStack {
            HStack {
                Button {
                    sound.state == .paused ? sound.resume() : sound.pause()
                } label: {
                    Image(systemName: sound.state == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Theme.softFill, in: Circle())
                }
                .tint(.primary)
                .disabled(!sound.isActive)
                .accessibilityLabel(sound.state == .paused ? "Resume" : "Pause")
                Spacer()
                Text(sound.elapsed.clockString)
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.softFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Recording time \(sound.elapsed.clockString), limit 3 hours")
            }
            Button {
                if sound.isActive { sound.stop() } else { Task { await sound.start() } }
            } label: {
                ZStack {
                    Circle().fill(Theme.ember).frame(width: 84, height: 84)
                        .shadow(color: Theme.ember.opacity(0.4), radius: 10, y: 4)
                    if sound.isActive {
                        RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "mic.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(sound.isActive ? "Stop recording" : "Start recording")
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(Theme.background.shadow(.drop(color: .black.opacity(0.06), radius: 8, y: -2)))
    }
}

/// One detected species. New species glow yellow for a few seconds; species heard in the last
/// few seconds show an animated "hearing now" indicator.
struct DetectionCard: View {
    let detection: LiveDetection
    let elapsed: TimeInterval
    let now: Date
    var showScientific = true

    private var isHighlighted: Bool { now < detection.newHighlightUntil }
    private var hearingNow: Bool { elapsed - detection.lastHeard < 4.5 }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                SpeciesThumb(url: detection.species.photoURL, group: detection.species.group, size: 72, corner: 8)
                    .opacity(detection.species.isGroupLevel ? 0.75 : 1)
                if detection.source == .apple {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9))
                        .padding(4)
                        .background(.thinMaterial, in: Circle())
                        .padding(3)
                        .accessibilityLabel("Detected by Apple sound recognition")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isHighlighted && detection.isNewToIndex {
                        Text("NEW").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.mossDeep)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.sunlight, in: Capsule())
                    }
                    Text(detection.species.isGroupLevel ? "Possible: \(detection.species.commonName)" : detection.species.commonName)
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }
                if showScientific || detection.species.isGroupLevel {
                    Text(detection.species.isGroupLevel ? "\(detection.species.scientificName) · group only" : detection.species.scientificName)
                        .font(.subheadline).italic()
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 10) {
                    Label(detection.firstHeard.clockString, systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                    ConfidenceMeter(value: Double(detection.maxConfidence))
                    if detection.count > 1 { Text("×\(detection.count)") }
                    if detection.caught && detection.isNewToIndex {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.moss)
                            .accessibilityLabel("Added to Wild Index")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            if hearingNow && !detection.species.isGroupLevel {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.moss)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .accessibilityLabel("Hearing now")
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
        .background(isHighlighted ? Theme.sunlight.opacity(0.55) : Color.clear)
        .animation(.easeInOut(duration: 0.6), value: isHighlighted)
        .contentShape(Rectangle())
    }
}
