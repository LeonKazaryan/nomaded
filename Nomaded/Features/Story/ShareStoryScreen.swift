import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Sharing the user's world as a story (ADR-019). The picture is ready at once and shows
/// first; the video is made only when asked for, over the picture with a progress bar, then
/// loops. Either goes to the share sheet: Instagram, Telegram, Photos, wherever.
struct ShareStoryScreen: View {
    let content: StoryContent
    let onClose: () -> Void

    private enum Format: Hashable {
        case picture
        case video
    }

    @State private var format = Format.picture
    @State private var picture: StoryPicture?
    @State private var video: URL?
    /// How far the video has come; `nil` while it isn't being made.
    @State private var videoProgress: Double?
    /// Bumped to make the video (again, after a failure). 0: not asked for yet.
    @State private var videoRequests = 0
    @State private var pictureFailed = false
    @State private var videoFailed = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpaceBackground()

            VStack(spacing: 16) {
                header
                card
                    .frame(maxHeight: .infinity)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                PillPicker(
                    options: [.init(id: Format.picture, title: "Picture"), .init(id: Format.video, title: "Video")],
                    selection: $format
                )
                .frame(maxWidth: 300)
                shareButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: Metrics.panelWidth)
        }
        .task { await makePicture() }
        .task(id: videoRequests) { await makeVideo() }
        .onChange(of: format) { _, format in
            if format == .video, video == nil, videoProgress == nil { videoRequests += 1 }
        }
        .onAppear {
            withAnimation(reduceMotion ? Motion.smooth : Motion.bouncy) { appeared = true }
        }
        .sensoryFeedback(Haptics.storyReady, trigger: video) { _, new in new != nil }
    }

    private var header: some View {
        HStack {
            Text("Share")
                .font(Typography.largeTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(Typography.headline)
                    .frame(width: 44, height: 44)
                    .glass(Circle())
                    .contentShape(.hoverEffect, Circle())
            }
            .buttonStyle(.pressable)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.top, 8)
    }

    /// The story as a phone shows it: 9:16, rounded, floating.
    private var card: some View {
        ZStack(alignment: .bottom) {
            SpaceStill(time: 0)
            if let picture {
                Image(decorative: picture.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if !pictureFailed {
                ProgressView()
                    .tint(.white)
                    .frame(maxHeight: .infinity)
            }
            if format == .video, let video {
                LoopingVideo(url: video)
                    .transition(.opacity)
            }
            if pictureFailed || (format == .video && videoFailed) {
                failure
            } else if format == .video, let videoProgress {
                making(videoProgress)
                    .transition(.opacity)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .animation(Motion.smooth, value: picture == nil)
        .animation(Motion.smooth, value: video)
        .animation(Motion.smooth, value: format)
        .accessibilityElement()
        .accessibilityLabel(format == .video && video == nil ? Text("Making the video…") : Text("Your story"))
    }

    /// Over the picture's lower part while the video is made: what's happening and how far.
    private func making(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Making the video…")
                .font(Typography.label)
            ProgressBar(progress: progress)
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
        .padding(14)
    }

    private var failure: some View {
        VStack(spacing: 12) {
            Text(pictureFailed ? "Couldn't make the picture" : "Couldn't make the video")
                .font(Typography.headline)
            Button("Try again") {
                if pictureFailed {
                    pictureFailed = false
                    Task { await makePicture() }
                } else {
                    videoRequests += 1
                }
            }
            .buttonStyle(.capsule(.subtle))
            .frame(maxWidth: 220)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard()
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let picture, format == .picture {
            ShareLink(item: StoryImageFile(url: picture.file), preview: preview(picture)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.capsule(.accent))
        } else if let picture, let video, format == .video {
            ShareLink(item: StoryVideoFile(url: video), preview: preview(picture)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.capsule(.accent))
        } else {
            Button {} label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.capsule(.subtle))
            .disabled(true)
        }
    }

    private func preview(_ picture: StoryPicture) -> SharePreview<Image, Never> {
        SharePreview("My world", image: Image(decorative: picture.image, scale: 1))
    }

    private func makePicture() async {
        do {
            picture = try await StoryFilm.picture(content)
            #if DEBUG
            // `-NomadedDebugShareVideo YES` (with `-NomadedDebugShare YES`): on to the video.
            if UserDefaults.standard.bool(forKey: "NomadedDebugShareVideo") { format = .video }
            #endif
        } catch is CancellationError {
            // Closed before it was done.
        } catch {
            pictureFailed = true
        }
    }

    private func makeVideo() async {
        guard videoRequests > 0, video == nil else { return }
        videoFailed = false
        videoProgress = 0
        defer { videoProgress = nil }
        do {
            video = try await StoryFilm.video(content) { videoProgress = $0 }
        } catch is CancellationError {
            // Closed before it was done.
        } catch {
            videoFailed = true
        }
    }
}

/// The video as a movie, not a link to a file: apps like Instagram only take it that way.
private struct StoryVideoFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie) { SentTransferredFile($0.url) }
    }
}

/// The picture as an image, not a link to a file.
private struct StoryImageFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { SentTransferredFile($0.url) }
    }
}

/// A thin bar for how far the video has come.
private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.18))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Palette.accentLight)
                        .frame(width: max(6, proxy.size.width * progress))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
    }
}

/// The finished film, playing silently round and round.
private struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?

        func play(_ url: URL) {
            // A silent preview mustn't stop the music someone's listening to.
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            let layer = layer as! AVPlayerLayer
            layer.player = player
            layer.videoGravity = .resizeAspectFill
            player.play()
        }
    }
}
