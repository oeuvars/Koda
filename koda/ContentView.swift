//
//  ContentView.swift
//  koda
//
//  Created by Anurag Das on 10/16/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = VideoConversionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            fileSelectionSection

            metadataSection

            presetSection

            conversionSection
        }
        .padding(24)
        .frame(minWidth: 780, minHeight: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Universal Video Converter")
                .font(.largeTitle)
                .bold()

            Text("Inspect a video with ffprobe and transcode it with ffmpeg using presets that adapt to the detected container and codecs.")
                .foregroundStyle(.secondary)

            Label("Requires ffmpeg and ffprobe to be installed and available in your PATH.", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Choose Video…") {
                    viewModel.chooseVideoFile()
                }
                .disabled(viewModel.isProcessing)

                if let url = viewModel.selectedFileURL {
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .bold()
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No video selected")
                        .foregroundStyle(.tertiary)
                }
            }

            if viewModel.isFetchingMetadata {
                ProgressView("Reading metadata…")
            }

            if !viewModel.metadataErrorMessage.isEmpty {
                Text(viewModel.metadataErrorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private var metadataSection: some View {
        Group {
            if let metadata = viewModel.metadata {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata")
                        .font(.title3)
                        .bold()

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 8) {
                        metadataRow(title: "Container", value: metadata.primaryFormat)
                        metadataRow(title: "Detected formats", value: metadata.formatSummary)
                        metadataRow(title: "Duration", value: metadata.duration ?? "Unknown")
                        metadataRow(title: "Video", value: metadata.videoSummary)
                        metadataRow(title: "Audio", value: metadata.audioSummary ?? "—")
                    }

                    if !viewModel.metadataRawOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ffprobe output")
                                .font(.subheadline)
                                .bold()
                            ScrollView {
                                Text(viewModel.metadataRawOutput)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                        }
                    }
                }
            }
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        GridRow {
            Text(title + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private var presetSection: some View {
        Group {
            if !viewModel.availablePresets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available conversion presets")
                        .font(.title3)
                        .bold()

                    Picker("Preset", selection: $viewModel.selectedPresetID) {
                        ForEach(viewModel.availablePresets) { preset in
                            Text(preset.name)
                                .tag(preset.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 360)

                    if viewModel.isShowingFallbackPresets {
                        Text("No metadata-specific recommendation was found, so the full preset library is shown.")
                            .foregroundStyle(.secondary)
                    }

                    if let preset = viewModel.selectedPreset {
                        Text(preset.description)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var conversionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.convertSelectedPreset()
                    }
                } label: {
                    Label("Convert", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canConvert)

                if viewModel.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                }

                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
                        .foregroundStyle(viewModel.statusColor)
                }
            }

            if !viewModel.ffmpegLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ffmpeg log")
                        .font(.subheadline)
                        .bold()
                    ScrollView {
                        Text(viewModel.ffmpegLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                }
            }
        }
    }
}

@MainActor
final class VideoConversionViewModel: ObservableObject {
    @Published var selectedFileURL: URL?
    @Published var metadata: FFProbeMetadata?
    @Published var metadataRawOutput: String = ""
    @Published var metadataErrorMessage: String = ""
    @Published var availablePresets: [ConversionPreset] = []
    @Published var selectedPresetID: UUID?
    @Published var statusMessage: String = ""
    @Published var ffmpegLog: String = ""
    @Published var isProcessing: Bool = false
    @Published var isFetchingMetadata: Bool = false
    @Published var isShowingFallbackPresets: Bool = false

    private let presetLibrary = ConversionPreset.library

    var selectedPreset: ConversionPreset? {
        availablePresets.first { $0.id == selectedPresetID }
    }

    var canConvert: Bool {
        !isProcessing && selectedFileURL != nil && selectedPreset != nil
    }

    var statusColor: Color {
        if statusMessage.starts(with: "Error") {
            return .red
        }

        if statusMessage.starts(with: "Finished") {
            return .green
        }

        return .secondary
    }

    func chooseVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .audiovisualContent, .mpeg4Movie, .quickTimeMovie]

        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            metadata = nil
            metadataRawOutput = ""
            metadataErrorMessage = ""
            availablePresets = []
            selectedPresetID = nil
            statusMessage = ""
            ffmpegLog = ""
            isShowingFallbackPresets = false

            Task {
                await readMetadata(for: url)
            }
        }
    }

    func readMetadata(for url: URL) async {
        isFetchingMetadata = true
        defer { isFetchingMetadata = false }

        do {
            let combinedOutput = try await ProcessExecutor.run(command: "ffprobe", arguments: ["-hide_banner", url.path])
            metadataRawOutput = combinedOutput
            metadata = FFProbeMetadata(output: combinedOutput)
            let presetResult = presets(for: metadata)
            availablePresets = presetResult.presets
            isShowingFallbackPresets = presetResult.isFallback
            selectedPresetID = availablePresets.first?.id
            statusMessage = "Metadata loaded"
        } catch {
            let errorMessage = "Error: failed to read metadata. Ensure ffprobe is installed and accessible in PATH. (\(error.localizedDescription))"
            metadataErrorMessage = errorMessage
            statusMessage = errorMessage
            availablePresets = presetLibrary
            isShowingFallbackPresets = true
            selectedPresetID = availablePresets.first?.id
        }
    }

    func convertSelectedPreset() async {
        guard let inputURL = selectedFileURL, let preset = selectedPreset else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }
        statusMessage = "Starting conversion…"

        let outputURL = makeOutputURL(for: preset, inputURL: inputURL)
        let arguments = preset.buildArguments(input: inputURL, output: outputURL)
        let commandLine = (["ffmpeg"] + arguments).map { argument -> String in
            if argument.contains(" ") {
                return "\"\(argument)\""
            }
            return argument
        }.joined(separator: " ")
        ffmpegLog = "$ \(commandLine)"

        do {
            let log = try await ProcessExecutor.run(command: "ffmpeg", arguments: arguments)
            statusMessage = "Finished: \(outputURL.lastPathComponent)"
            let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ffmpegLog += "\n\nffmpeg completed without additional output."
            } else {
                ffmpegLog += "\n\n" + trimmed
            }
            ffmpegLog += "\n\nSaved to: \(outputURL.path)"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            let message = (error as? ProcessError)?.displayMessage ?? error.localizedDescription
            ffmpegLog += "\n\n" + message
        }
    }

    private func makeOutputURL(for preset: ConversionPreset, inputURL: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        var candidate = inputURL.deletingLastPathComponent().appendingPathComponent(baseName).appendingPathExtension(preset.outputExtension)

        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let newName = "\(baseName) (\(index))"
            candidate = inputURL.deletingLastPathComponent()
                .appendingPathComponent(newName)
                .appendingPathExtension(preset.outputExtension)
            index += 1
        }

        return candidate
    }

    private func presets(for metadata: FFProbeMetadata?) -> (presets: [ConversionPreset], isFallback: Bool) {
        guard let metadata else { return (presetLibrary, true) }
        let identifiers = metadata.formatIdentifiers

        let filtered = presetLibrary.filter { preset in
            preset.supportedContainers.isEmpty || !identifiers.isDisjoint(with: preset.supportedContainers)
        }

        if filtered.isEmpty {
            return (presetLibrary, true)
        }

        return (filtered, false)
    }
}

struct FFProbeMetadata {
    let primaryFormat: String
    let formatIdentifiers: Set<String>
    let duration: String?
    let videoSummary: String
    let audioSummary: String?
    let formatSummary: String

    init(output: String) {
        let lines = output.split(separator: "\n").map(String.init)
        var primaryFormat = "Unknown"
        var identifiers = Set<String>()
        var duration: String?
        var videoSummary = "Unknown"
        var audioSummary: String?

        for line in lines {
            if line.starts(with: "Input #0,") {
                if let fromRange = line.range(of: ", from") {
                    let formatSegment = line[line.index(line.startIndex, offsetBy: 9)..<fromRange.lowerBound]
                    let rawIdentifiers = formatSegment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    identifiers.formUnion(rawIdentifiers.map { $0.lowercased() })
                    primaryFormat = rawIdentifiers.first?.uppercased() ?? "Unknown"
                }
            }

            if line.contains("Duration:") {
                let parts = line.components(separatedBy: ",")
                if let durationPart = parts.first(where: { $0.contains("Duration:") }) {
                    duration = durationPart.replacingOccurrences(of: "Duration:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }

            if line.contains("Video:") {
                if let range = line.range(of: "Video:") {
                    videoSummary = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    videoSummary = line.trimmingCharacters(in: .whitespaces)
                }
            }

            if line.contains("Audio:") {
                if let range = line.range(of: "Audio:") {
                    audioSummary = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    audioSummary = line.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        self.primaryFormat = primaryFormat
        self.formatIdentifiers = identifiers
        self.duration = duration
        self.videoSummary = videoSummary
        self.audioSummary = audioSummary
        if identifiers.isEmpty {
            self.formatSummary = primaryFormat
        } else {
            self.formatSummary = identifiers.sorted().joined(separator: ", ").uppercased()
        }
    }
}

struct ConversionPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let outputExtension: String
    let supportedContainers: Set<String>
    let ffmpegOptions: [String]

    func buildArguments(input: URL, output: URL) -> [String] {
        var arguments: [String] = ["-hide_banner", "-y", "-i", input.path]
        arguments.append(contentsOf: ffmpegOptions)
        arguments.append(output.path)
        return arguments
    }

    static let library: [ConversionPreset] = [
        ConversionPreset(
            name: "High Compatibility MP4 (H.264/AAC)",
            description: "Generate an MP4 with H.264 video and AAC audio for maximum device compatibility.",
            outputExtension: "mp4",
            supportedContainers: Set(["mov", "mp4", "m4v", "mkv", "avi", "webm", "flv"]),
            ffmpegOptions: ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-c:a", "aac", "-b:a", "192k"]
        ),
        ConversionPreset(
            name: "HEVC MP4 (H.265)",
            description: "Compress with the HEVC codec for smaller files at similar quality.",
            outputExtension: "mp4",
            supportedContainers: Set(["mov", "mp4", "m4v", "mkv"]),
            ffmpegOptions: ["-c:v", "libx265", "-tag:v", "hvc1", "-preset", "slow", "-crf", "24", "-c:a", "aac", "-b:a", "192k"]
        ),
        ConversionPreset(
            name: "ProRes 422 MOV",
            description: "Create a mezzanine-quality Apple ProRes 422 file for editing workflows.",
            outputExtension: "mov",
            supportedContainers: Set(["mov", "mp4", "m4v", "mxf", "avi"]),
            ffmpegOptions: ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le", "-c:a", "pcm_s16le"]
        ),
        ConversionPreset(
            name: "WebM VP9",
            description: "Produce a WebM container with VP9 video and Opus audio for web delivery.",
            outputExtension: "webm",
            supportedContainers: Set(["mov", "mp4", "m4v", "mkv", "flv", "avi", "webm"]),
            ffmpegOptions: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-c:a", "libopus", "-b:a", "128k"]
        ),
        ConversionPreset(
            name: "Legacy AVI (MPEG-4 Part 2)",
            description: "Create an AVI file compatible with older hardware and software.",
            outputExtension: "avi",
            supportedContainers: Set(["mov", "mp4", "m4v", "mkv", "wmv", "flv", "mpg", "mpeg", "avi"]),
            ffmpegOptions: ["-c:v", "mpeg4", "-q:v", "5", "-c:a", "libmp3lame", "-b:a", "160k"]
        ),
        ConversionPreset(
            name: "Animated GIF",
            description: "Turn the video into an animated GIF with palette generation for better colors.",
            outputExtension: "gif",
            supportedContainers: Set<String>(),
            ffmpegOptions: [
                "-filter_complex",
                "[0:v] fps=12,scale=640:-1:flags=lanczos,split [a][b];[a] palettegen=stats_mode=diff [p];[b][p] paletteuse=new=1",
                "-an"
            ]
        ),
        ConversionPreset(
            name: "Matroska H.264",
            description: "Wrap H.264 video and AAC audio in an MKV container.",
            outputExtension: "mkv",
            supportedContainers: Set(["mov", "mp4", "m4v", "avi", "mpg", "mpeg", "flv", "mkv", "ts"]),
            ffmpegOptions: ["-c:v", "libx264", "-preset", "faster", "-crf", "20", "-c:a", "aac", "-b:a", "192k"]
        ),
        ConversionPreset(
            name: "Audio Only (AAC m4a)",
            description: "Extract the audio track into an AAC .m4a file.",
            outputExtension: "m4a",
            supportedContainers: Set<String>(),
            ffmpegOptions: ["-vn", "-c:a", "aac", "-b:a", "192k"]
        )
    ]
}

enum ProcessExecutor {
    static func run(command: String, arguments: [String], collectStdout: Bool = false) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [command] + arguments

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()

                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdoutString = String(decoding: stdoutData, as: UTF8.self)
                    let stderrString = String(decoding: stderrData, as: UTF8.self)

                    guard process.terminationStatus == 0 else {
                        let rawMessage = stderrString.isEmpty ? stdoutString : stderrString
                        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: ProcessError.exit(status: process.terminationStatus, message: message))
                        return
                    }

                    if collectStdout {
                        continuation.resume(returning: stdoutString)
                    } else {
                        let needsJoin = !stderrString.isEmpty && !stdoutString.isEmpty
                        let separator = needsJoin && !stderrString.hasSuffix("\n") ? "\n" : ""
                        let combined = stderrString + separator + stdoutString
                        continuation.resume(returning: combined)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum ProcessError: LocalizedError {
    case exit(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case let .exit(status, message):
            return "Process exited with status \(status): \(message)"
        }
    }

    var displayMessage: String {
        switch self {
        case let .exit(_, message):
            return message.isEmpty ? "Process exited with an unknown error." : message
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
