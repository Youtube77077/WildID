import AVFoundation
import SwiftData
import SwiftUI

// MARK: - Playback spectrogram

/// Renders the spectrogram of a ±4 s window around the playhead of an audio file.
@MainActor
@Observable
final class PlaybackSpectrogramModel {
    private(set) var image: CGImage?
    private var lastKey = -1
    private var task: Task<Void, Never>?
    static let window: Double = 8

    func update(url: URL, time: TimeInterval, dark: Bool) {
        let key = Int(time * 4) * (dark ? -1 : 1)
        guard key != lastKey else { return }
        lastKey = key
        task?.cancel()
        task = Task.detached(priority: .utility) { [weak self] in
            let start = max(0, time - Self.window / 2)
            guard let samples = Self.read(url: url, from: start, seconds: Self.window) else { return }
            // Pad the beginning so the playhead stays centered at the start of the file.
            let pad = Int(max(0, Self.window / 2 - time) * AudioCaptureEngine.analysisSampleRate)
            let padded = [Float](repeating: 0, count: pad) + samples
            let img = StaticSpectrogram.image(samples: padded, dark: dark)
            if Task.isCancelled { return }
            await MainActor.run { self?.image = img }
        }
    }

    nonisolated static func read(url: URL, from start: TimeInterval, seconds: TimeInterval) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else { return nil }
        let sr = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(start * sr)
        guard startFrame < file.length else { return nil }
        file.framePosition = startFrame
        let count = AVAudioFrameCount(min(Double(file.length - startFrame), seconds * sr))
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return nil }
        try? file.read(into: buffer, frameCount: count)
        guard let ch = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
        if abs(sr - AudioCaptureEngine.analysisSampleRate) < 1 { return samples }
        // Simple resample for clips recorded at another rate.
        let ratio = sr / AudioCaptureEngine.analysisSampleRate
        return (0..<Int(Double(samples.count) / ratio)).map { samples[min(samples.count - 1, Int(Double($0) * ratio))] }
    }
}

struct RecordingPlayerCard: View {
    let id: String
    let url: URL
    let duration: TimeInterval
    var markers: [TimeInterval] = []

    @Environment(AudioPlayer.self) private var player
    @Environment(\.colorScheme) private var colorScheme
    @State private var spectro = PlaybackSpectrogramModel()

    private var isCurrent: Bool { player.currentID == id }
    private var time: TimeInterval { isCurrent ? player.currentTime : 0 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Theme.softFill.opacity(0.5)
                if let image = spectro.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                }
                Rectangle().fill(Color.red.opacity(0.8)).frame(width: 1.5)
                Button {
                    player.toggle(id: id, url: url)
                } label: {
                    Image(systemName: player.isPlayingItem(id) ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.black.opacity(0.85)))
                }
                .accessibilityLabel(player.isPlayingItem(id) ? "Pause" : "Play")
                VStack {
                    Spacer()
                    HStack {
                        Text(isCurrent ? "\(time.clockString) / \(duration.clockString)" : duration.clockString)
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Scrubber with detection markers.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.softFill).frame(height: 6)
                    Capsule().fill(Theme.moss).frame(width: geo.size.width * CGFloat(duration > 0 ? min(1, time / duration) : 0), height: 6)
                    ForEach(Array(markers.enumerated()), id: \.offset) { _, m in
                        Circle().fill(Theme.sunlight).frame(width: 7, height: 7)
                            .offset(x: geo.size.width * CGFloat(duration > 0 ? m / duration : 0) - 3.5)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    let t = max(0, min(duration, Double(v.location.x / geo.size.width) * duration))
                    if isCurrent { player.seek(to: t) } else { player.play(id: id, url: url, from: t) }
                })
            }
            .frame(height: 20)
            if let blocked = player.blockedMessage {
                Text(blocked).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { spectro.update(url: url, time: 0, dark: colorScheme == .dark) }
        .onChange(of: player.currentTime) { _, t in
            if isCurrent { spectro.update(url: url, time: t, dark: colorScheme == .dark) }
        }
        .onChange(of: colorScheme) { _, scheme in spectro.update(url: url, time: time, dark: scheme == .dark) }
    }
}

struct DetectionSeekRow: View {
    let commonName: String
    let scientificName: String
    let photoURL: URL?
    let group: AnimalGroup
    let isGroupLevel: Bool
    let offsets: [TimeInterval]
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 14) {
            SpeciesThumb(url: photoURL, group: group, size: 64, corner: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(isGroupLevel ? "Possible: \(commonName)" : commonName).font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                Text("\(offsets.count) \(offsets.count == 1 ? "time" : "times") · first at \((offsets.min() ?? 0).clockString)")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Divider().frame(height: 40)
            Button { onSeek(offsets.min() ?? 0) } label: {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Play where \(commonName) was heard")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Session summary (after stopping)

struct SessionSummaryView: View {
    let onDone: () -> Void
    @Environment(SoundIDSession.self) private var sound
    @Environment(AudioPlayer.self) private var player
    @State private var savedURL: URL?
    @State private var confirmClose = false

    var body: some View {
        if let summary = sound.summary {
            let url = savedURL ?? summary.fileURL
            let species = summary.detections.filter { !$0.species.isGroupLevel }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(summary.startedAt.formatted(.dateTime.month(.wide).day())) • \(summary.placeName ?? "Sound ID")")
                        .font(.system(size: 26, weight: .heavy))
                        .lineLimit(1)
                    HStack {
                        Text("\(summary.startedAt.formatted(date: .omitted, time: .shortened)) • \(species.count) \(species.count == 1 ? "animal" : "animals") • \(summary.duration.clockString)")
                            .font(.title3).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if summary.savedRecordingID == nil {
                            Button("Save") { save() }
                                .font(.system(size: 18, weight: .medium))
                                .padding(.horizontal, 20).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
                                .tint(.primary)
                        } else {
                            Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.moss).font(.headline)
                        }
                    }
                    if summary.savedRecordingID == nil {
                        Text("About \(FileStore.formatted(FileStore.size(of: url))) · Save to keep the full recording in Sound ID Sessions. Animals you caught stay in your Wild Index either way.")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    RecordingPlayerCard(id: summary.id.uuidString, url: url, duration: summary.duration,
                                        markers: summary.detections.flatMap(\.offsets))
                    if summary.detections.isEmpty {
                        EmptyStateView(symbol: "ear", title: "Nothing identified",
                                       message: "No animal sounds were confidently identified. Try somewhere quieter, closer to the sound, or at dawn when animals are most vocal.")
                    }
                    ForEach(summary.detections) { d in
                        NavigationLink(value: d.species) {
                            DetectionSeekRow(commonName: d.species.commonName, scientificName: d.species.scientificName,
                                             photoURL: d.species.photoURL, group: d.species.group, isGroupLevel: d.species.isGroupLevel,
                                             offsets: d.offsets) { t in
                                player.play(id: summary.id.uuidString, url: url, from: max(0, t - 0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(Theme.gutter)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)) }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { player.stop(); Task { await sound.start() } } label: { Label("New session", systemImage: "mic.fill") }
                }
            }
            .confirmationDialog("Keep this recording?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Save recording") { save(); finish() }
                Button("Discard recording", role: .destructive) { player.stop(); sound.discard(); onDone() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Animals you caught stay in your Wild Index either way.")
            }
        }
    }

    private func save() {
        if let rec = sound.save() { savedURL = rec.fileURL }
    }

    private func close() {
        if sound.summary?.savedRecordingID == nil { confirmClose = true } else { finish() }
    }

    private func finish() {
        player.stop()
        sound.discard()   // the file was moved when saved, so this only resets state
        onDone()
    }
}

// MARK: - Saved sessions

struct RecordingsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayer.self) private var player
    @Query(sort: \SavedRecording.startedAt, order: .reverse) private var recordings: [SavedRecording]
    @State private var confirmDeleteAll = false

    var totalSize: Int64 { recordings.reduce(0) { $0 + $1.fileSize } }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(recordings.count) saved \(recordings.count == 1 ? "session" : "sessions")").font(.headline)
                        Text("Using \(FileStore.formatted(totalSize)) on this iPhone").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "internaldrive").font(.title2).foregroundStyle(Theme.fern)
                }
            } footer: {
                Text("Recordings are AAC audio (about 28 MB per hour). They're also visible in the Files app under On My iPhone › WildID › Recordings.")
            }
            if recordings.isEmpty {
                EmptyStateView(symbol: "waveform", title: "No saved sessions",
                               message: "After a Sound ID session, tap Save to keep the recording here.")
                    .listRowBackground(Color.clear)
            }
            ForEach(recordings) { rec in
                NavigationLink(value: rec.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text(rec.placeName ?? "Unknown place").font(.subheadline).foregroundStyle(Theme.secondaryText)
                        HStack(spacing: 12) {
                            Label(rec.duration.clockString, systemImage: "clock")
                            Label("\(rec.detections.filter { !$0.isGroupLevel }.count) animals", systemImage: "pawprint")
                            Label(FileStore.formatted(rec.fileSize), systemImage: "internaldrive")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { idx in idx.map { recordings[$0] }.forEach(delete) }
        }
        .navigationTitle("Sound ID Sessions")
        .navigationDestination(for: UUID.self) { id in
            if let rec = recordings.first(where: { $0.id == id }) { RecordingDetailView(recording: rec) }
        }
        .wildDestinations()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Delete all recordings", role: .destructive) { confirmDeleteAll = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(recordings.isEmpty)
            }
        }
        .confirmationDialog("Delete all \(recordings.count) recordings (\(FileStore.formatted(totalSize)))?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { recordings.forEach(delete) }
        } message: { Text("Your Wild Index and catches are not affected.") }
    }

    private func delete(_ rec: SavedRecording) {
        if player.currentID == rec.id.uuidString { player.stop() }
        try? FileManager.default.removeItem(at: rec.fileURL)
        context.delete(rec)
        try? context.save()
    }
}

struct RecordingDetailView: View {
    let recording: SavedRecording
    @Environment(AudioPlayer.self) private var player
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(recording.startedAt.formatted(.dateTime.month(.wide).day())) • \(recording.placeName ?? "Sound ID")")
                    .font(.system(size: 26, weight: .heavy)).lineLimit(2)
                Text("\(recording.startedAt.formatted(date: .omitted, time: .shortened)) • \(recording.detections.filter { !$0.isGroupLevel }.count) animals • \(FileStore.formatted(recording.fileSize))")
                    .font(.title3).foregroundStyle(Theme.secondaryText)
                RecordingPlayerCard(id: recording.id.uuidString, url: recording.fileURL, duration: recording.duration,
                                    markers: recording.detections.flatMap(\.offsets))
                ForEach(recording.sortedDetections) { d in
                    NavigationLink(value: SpeciesRef(scientificName: d.scientificName, commonName: d.commonName, taxonID: d.taxonID,
                                                     photoURL: d.photoURL, group: d.group, isGroupLevel: d.isGroupLevel)) {
                        DetectionSeekRow(commonName: d.commonName, scientificName: d.scientificName, photoURL: d.photoURL,
                                         group: d.group, isGroupLevel: d.isGroupLevel, offsets: d.offsets) { t in
                            player.play(id: recording.id.uuidString, url: recording.fileURL, from: max(0, t - 0.5))
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .padding(Theme.gutter)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: recording.fileURL) { Image(systemName: "square.and.arrow.up") }
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
            }
        }
        .confirmationDialog("Delete this recording (\(FileStore.formatted(recording.fileSize)))?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                player.stop()
                try? FileManager.default.removeItem(at: recording.fileURL)
                context.delete(recording)
                try? context.save()
                dismiss()
            }
        }
        .onDisappear { if player.currentID == recording.id.uuidString { player.stop() } }
    }
}
