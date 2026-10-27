import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import ConsoleCore

/// Creator suite (Kingdom t1083s4364): BAMA screens that drive Apple's creator apps through rea-mcp (every write/export/
/// draft is HELD for approval) and native CreatorKit rebuilds that run locally at $0. Nothing posts automatically.
@MainActor @Observable final class CreatorHub {
    let rea = ReaMcpClient.mac()
    var apps: [String: String] = [:]          // key → app path (installed)
    var postizKey = "unknown"
    var shortcuts: [String] = []
    var queued: [(id: String, summary: String)] = []
    var message: String?
    var error: String?
    static let outDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("m3ta-os/creator/out", isDirectory: true)

    func refresh() async {
        do {
            let s = try await rea.callRead("rea_native_status")
            let o = s["output"] as? [String: Any] ?? [:]
            apps = (o["apps"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            postizKey = (o["postiz"] as? [String: Any])?["key"] as? String ?? "unknown"
            error = nil
        } catch { self.error = "rea-mcp creator tools not loaded yet (\(error.localizedDescription)). Restart rea-mcp on the rea-native-tools branch after approval." }
        if let l = try? await rea.callRead("rea_shortcuts_list"), let o = l["output"] as? [String: Any] { shortcuts = o["shortcuts"] as? [String] ?? [] }
    }
    func queue(_ a: CreatorAction) async {
        do { let id = try await CreatorQueue(rea: rea).enqueue(a); queued.insert((id, a.summary), at: 0); message = "Held for your approval: \(a.summary) (\(id)). Approve it in JARVIS ▸ rea Approvals." ; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func installed(_ k: String) -> Bool { apps[k] != nil }
    func outURL(_ name: String) -> URL { try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true); return Self.outDir.appendingPathComponent(name) }
}

struct CreatorBanner: View {
    @Environment(CreatorHub.self) var hub
    var body: some View {
        if let m = hub.message { Label(m, systemImage: "hourglass").foregroundStyle(Color.m3taGold).font(.callout) }
        if let e = hub.error { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(Color.statusWarn).font(.callout) }
    }
}

struct PathRow: View {
    let label: String; @Binding var path: String; var types: [UTType] = [.item]
    @State private var picking = false
    var body: some View {
        HStack { Text(label).frame(width: 110, alignment: .leading); TextField("~/…", text: $path).textFieldStyle(.roundedBorder).font(.callout.monospaced()); Button("Choose…") { picking = true } }
            .fileImporter(isPresented: $picking, allowedContentTypes: types) { if case .success(let u) = $0 { path = u.path } }
    }
}

// MARK: Studio overview
struct CreatorStudioView: View {
    @Environment(CreatorHub.self) var hub
    let keys: [CreatorStage: String] = [.edit: "finalcut", .thumbnails: "pixelmator", .voice: "logic", .export: "compressor"]
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Creator Studio", subtitle: "Final Cut · Compressor · Pixelmator · Voicebox→Logic · Speech captions · Postiz drafts — driven via rea-mcp, every write held for you", icon: "film.stack")
            CreatorBanner()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230))], spacing: 12) {
                ForEach(CreatorStage.allCases) { s in
                    let k = keys[s]
                    StatusCard(title: s.rawValue.capitalized + " · " + s.app, value: k.map { hub.installed($0) ? "Installed" : "Native only" } ?? (s == .publish ? "Drafts" : "On-device"),
                               detail: "Native fallback: \(s.native)" + (s.reaTool.map { " · \($0) (gated)" } ?? ""), icon: icon(s),
                               tone: k.map { hub.installed($0) ? .good : .warn } ?? .neutral)
                }
            }
            GlassCard { VStack(alignment: .leading, spacing: 6) {
                Text("Rules").font(.headline)
                Text("$0 · local only · 127.0.0.1 · no decompiling — only sdef, Shortcuts, FCPXML, Compressor CLI, AppleScript").font(.callout)
                Text("Postiz key: \(hub.postizKey) · Shortcuts found: \(hub.shortcuts.count) · Queued this session: \(hub.queued.count)").font(.caption).foregroundStyle(.secondary)
            } }
            Button("Refresh") { Task { await hub.refresh() } }.buttonStyle(.glass)
        }.padding(24) }.task { await hub.refresh() }
    }
    func icon(_ s: CreatorStage) -> String { switch s { case .edit: "scissors"; case .thumbnails: "photo.on.rectangle"; case .voice: "waveform"; case .captions: "captions.bubble"; case .export: "square.and.arrow.up.on.square"; case .publish: "paperplane" } }
}

// MARK: Edit (Final Cut via FCPXML + native AVFoundation)
struct CreatorEditView: View {
    @Environment(CreatorHub.self) var hub
    @State private var title = "BAMA Edit"
    @State private var clips: [EditClip] = [EditClip()]
    @State private var preview = ""
    @State private var busy = false
    struct EditClip: Identifiable { let id = UUID(); var path = ""; var start = 0.0; var duration = 5.0 }
    var ranges: [ClipRange] { clips.filter { !$0.path.isEmpty }.map { ClipRange(url: URL(fileURLWithPath: $0.path), start: $0.start, duration: $0.duration) } }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Edit", subtitle: "Final Cut Pro 12.4 via FCPXML (import is gated) · native trim/concat with AVFoundation", icon: "scissors")
            CreatorBanner()
            GlassCard { VStack(alignment: .leading, spacing: 8) {
                TextField("Project title", text: $title).textFieldStyle(.roundedBorder)
                ForEach($clips) { $c in HStack {
                    PathRow(label: "Clip", path: $c.path, types: [.movie])
                    Stepper("in \(c.start, specifier: "%.1f")s", value: $c.start, in: 0...36000, step: 0.5).frame(width: 120)
                    Stepper("len \(c.duration, specifier: "%.1f")s", value: $c.duration, in: 0.5...36000, step: 0.5).frame(width: 130)
                } }
                HStack {
                    Button("Add clip", systemImage: "plus") { clips.append(EditClip()) }
                    Button("Preview FCPXML") { preview = FCPXML.build(title: title, clips: ranges) }.disabled(ranges.isEmpty)
                    Button("Queue: open in Final Cut", systemImage: "hourglass") { Task { await hub.queue(.fcpxmlImport(title: title, clips: ranges, path: hub.outURL("\(title.replacingOccurrences(of: "/", with: "-")).fcpxml").path)) } }.buttonStyle(.glassProminent).disabled(ranges.isEmpty)
                    Button("Native render (local)") { Task { busy = true; defer { busy = false }
                        do { let c = try await CreatorMedia.compose(ranges); let u = hub.outURL("edit-\(Int(Date().timeIntervalSince1970)).mov"); try await CreatorMedia.export(c, to: u); hub.message = "Rendered locally: \(u.path)" } catch { hub.error = error.localizedDescription } } }.disabled(ranges.isEmpty || busy)
                    if busy { ProgressView().controlSize(.small) }
                }
            } }
            if !preview.isEmpty { GlassCard { ScrollView(.horizontal) { Text(preview).font(.caption.monospaced()).textSelection(.enabled) } } }
        }.padding(24) }
    }
}

// MARK: Thumbnails
struct CreatorThumbsView: View {
    @Environment(CreatorHub.self) var hub
    @State private var input = ""
    @State private var img: CGImage?
    @State private var w = 1280
    @State private var h = 720
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Thumbnails", subtitle: "Pixelmator Pro export_thumbnail (gated) · native Core Image + Vision saliency crop", icon: "photo.on.rectangle")
            CreatorBanner()
            GlassCard { VStack(alignment: .leading, spacing: 8) {
                PathRow(label: "Image", path: $input, types: [.image])
                HStack { Stepper("Width \(w)", value: $w, in: 320...3840, step: 160); Stepper("Height \(h)", value: $h, in: 180...2160, step: 90) }
                HStack {
                    Button("Native preview") { do { img = try CreatorThumbnail.make(from: CreatorThumbnail.load(URL(fileURLWithPath: input)), width: w, height: h) } catch { hub.error = error.localizedDescription } }.disabled(input.isEmpty)
                    Button("Save native PNG") { if let img { let u = hub.outURL("thumb-\(Int(Date().timeIntervalSince1970)).png"); do { try CreatorThumbnail.writePNG(img, to: u); hub.message = "Saved \(u.path)" } catch { hub.error = error.localizedDescription } } }.disabled(img == nil)
                    Button("Queue: Pixelmator Pro export", systemImage: "hourglass") { Task { await hub.queue(.pixelmatorThumbnail(input: input, output: hub.outURL("pxm-thumb-\(Int(Date().timeIntervalSince1970)).png").path, width: w, height: h)) } }.buttonStyle(.glassProminent).disabled(input.isEmpty || !hub.installed("pixelmator"))
                }
            } }
            if let img { Image(decorative: img, scale: 2).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 640).clipShape(.rect(cornerRadius: 12)) }
        }.padding(24) }
    }
}

// MARK: Voice & Audio
struct CreatorVoiceView: View {
    @Environment(CreatorHub.self) var hub
    @State private var input = ""
    @State private var target: Float = -1
    @State private var shortcut = ""
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Voice & Audio", subtitle: "Voicebox (local TTS) → Logic Pro · native AVAudioEngine peak-normalize", icon: "waveform")
            CreatorBanner()
            GlassCard { VStack(alignment: .leading, spacing: 8) {
                Text("Normalize (native)").font(.headline)
                PathRow(label: "Audio", path: $input, types: [.audio])
                HStack { Stepper("Target \(target, specifier: "%.0f") dBFS", value: $target, in: -12...0, step: 1)
                    Button("Normalize locally") { do { let u = hub.outURL("norm-\(Int(Date().timeIntervalSince1970)).caf"); let g = try CreatorAudio.normalize(URL(fileURLWithPath: input), to: u, targetDBFS: target); hub.message = String(format: "Normalized (%+.1f dB) → %@", g, u.path) } catch { hub.error = error.localizedDescription } }.disabled(input.isEmpty) }
            } }
            GlassCard { VStack(alignment: .leading, spacing: 8) {
                Text("Hand off via Shortcuts (gated)").font(.headline)
                Text("Voicebox renders and Logic Pro bounces are wired as Shortcuts you own; BAMA only queues them. Logic Pro: \(hub.installed("logic") ? "installed" : "not found").").font(.caption).foregroundStyle(.secondary)
                Picker("Shortcut", selection: $shortcut) { Text("Choose…").tag(""); ForEach(hub.shortcuts, id: \.self) { Text($0).tag($0) } }
                Button("Queue Shortcut", systemImage: "hourglass") { Task { await hub.queue(.shortcut(name: shortcut, input: input.isEmpty ? nil : input)) } }.buttonStyle(.glassProminent).disabled(shortcut.isEmpty)
            } }
        }.padding(24) }.task { if hub.shortcuts.isEmpty { await hub.refresh() } }
    }
}

// MARK: Captions
struct CreatorCaptionsView: View {
    @Environment(CreatorHub.self) var hub
    @State private var input = ""
    @State private var srt = ""
    @State private var busy = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Captions", subtitle: "On-device Speech (never leaves the Mac) → SRT · whisper.cpp output accepted as the alternative", icon: "captions.bubble")
            CreatorBanner()
            GlassCard { VStack(alignment: .leading, spacing: 8) {
                PathRow(label: "Media", path: $input, types: [.audiovisualContent])
                HStack {
                    Button("Transcribe on-device") { Task { busy = true; defer { busy = false }
                        do { srt = CreatorCaptions.srt(CreatorCaptions.cues(try await CreatorCaptions.transcribe(URL(fileURLWithPath: input)))) } catch { hub.error = error.localizedDescription } } }.disabled(input.isEmpty || busy)
                    Button("Save .srt") { let u = hub.outURL("captions-\(Int(Date().timeIntervalSince1970)).srt"); do { try srt.write(to: u, atomically: true, encoding: .utf8); hub.message = "Saved \(u.path)" } catch { hub.error = error.localizedDescription } }.disabled(srt.isEmpty)
                    if busy { ProgressView().controlSize(.small) }
                }
            } }
            GlassCard { TextEditor(text: $srt).font(.callout.monospaced()).frame(minHeight: 220) }
        }.padding(24) }
    }
}

// MARK: Export
struct CreatorExportView: View {
    @Environment(CreatorHub.self) var hub
    @State private var source = ""
    @State private var setting = ""
    @State private var location = CreatorHub.outDir.path
    @State private var preset = AVAssetExportPresetHEVCHighestQuality
    @State private var busy = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Export", subtitle: "Compressor CLI (gated) · native AVAssetExportSession fallback", icon: "square.and.arrow.up.on.square")
            CreatorBanner()
            GlassCard { VStack(alignment: .leading, spacing: 8) {
                PathRow(label: "Source", path: $source, types: [.movie])
                PathRow(label: "Setting", path: $setting)
                PathRow(label: "Output folder", path: $location, types: [.folder])
                HStack {
                    Button("Queue: Compressor encode", systemImage: "hourglass") { Task { await hub.queue(.compressorEncode(source: source, setting: setting, location: location)) } }.buttonStyle(.glassProminent).disabled(source.isEmpty || setting.isEmpty || !hub.installed("compressor"))
                    Picker("Native preset", selection: $preset) { Text("HEVC best").tag(AVAssetExportPresetHEVCHighestQuality); Text("H.264 best").tag(AVAssetExportPresetHighestQuality); Text("1080p").tag(AVAssetExportPreset1920x1080) }.frame(width: 220)
                    Button("Export natively") { Task { busy = true; defer { busy = false }
                        do { let u = hub.outURL("export-\(Int(Date().timeIntervalSince1970)).mov"); try await CreatorMedia.export(AVURLAsset(url: URL(fileURLWithPath: source)), to: u, preset: preset); hub.message = "Exported \(u.path)" } catch { hub.error = error.localizedDescription } } }.disabled(source.isEmpty || busy)
                    if busy { ProgressView().controlSize(.small) }
                }
            } }
        }.padding(24) }
    }
}

// MARK: Publish queue (Postiz drafts only)
struct CreatorPublishView: View {
    @Environment(CreatorHub.self) var hub
    @State private var content = ""
    @State private var channels = ""
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Publish queue", subtitle: "Postiz is the only way out · DRAFTS only · each draft held for your approval · nothing auto-posts", icon: "paperplane")
            CreatorBanner()
            GlassCard { VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $content).font(.body).frame(minHeight: 120)
                TextField("Postiz channel ids (comma separated)", text: $channels).textFieldStyle(.roundedBorder)
                HStack { Text("Postiz key: \(hub.postizKey)").font(.caption).foregroundStyle(.secondary); Spacer()
                    Button("Queue Postiz draft", systemImage: "hourglass") { Task { await hub.queue(.postizDraft(content: content, integrations: channels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })) } }.buttonStyle(.glassProminent).disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            } }
            Text("Held this session").font(.headline)
            if hub.queued.isEmpty { ContentUnavailableView("Nothing queued", systemImage: "tray", description: Text("Queued items appear in JARVIS ▸ rea Approvals; approve runs once with Touch ID.")) }
            ForEach(hub.queued, id: \.id) { q in GlassCard { HStack { Image(systemName: "hourglass"); Text(q.summary); Spacer(); Text(q.id).font(.caption.monospaced()).foregroundStyle(.secondary) } } }
        }.padding(24) }
    }
}
