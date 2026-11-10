import AVFoundation
import SwiftUI

/// Sharing the user's world as a story (ADR-019). The film develops in a phone-shaped card
/// frame by frame as it's made, then loops; underneath, video or picture and the share
/// sheet: Instagram, Telegram, Photos, wherever.
struct ShareStoryScreen: View {
    let content: StoryContent
    let onClose: () -> Void

    private enum Format: Hashable {
        case video
        case picture
    }

    @State private var format = Format.video
    @State private var files: StoryFiles?
    /// The film's latest frame while it's being made.
    @State private var frame: CGImage?
    /// The finished picture: the film's last frame.
    @State private var still: CGImage?
    @State private var progress = 0.0
    @State private var failed = false
    @State private var attempts = 0
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
                    options: [.init(id: Format.video, title: "Video"), .init(id: Format.picture, title: "Picture")],
                    selection: $format
                )
                .frame(maxWidth: 300)
                shareButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: Metrics.panelWidth)
        }
        .task(id: attempts) { await make() }
        .onAppear {
            withAnimation(reduceMotion ? Motion.smooth : Motion.bouncy) { appeared = true }
        }
        .sensoryFeedback(Haptics.storyReady, trigger: files) { _, new in new != nil }
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
            if let files, format == .video, !reduceMotion {
                LoopingVideo(url: files.video)
                    .transition(.opacity)
            } else if let image = files == nil ? (reduceMotion ? nil : frame) : still {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            if failed {
                failure
            } else if files == nil {
                ProgressBar(progress: progress)
                    .padding(20)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .accessibilityElement()
        .accessibilityLabel(files == nil ? Text("Making the video…") : Text("Your story"))
    }

    private var failure: some View {
        VStack(spacing: 12) {
            Text("Couldn't make the video")
                .font(Typography.headline)
            Button("Try again") { attempts += 1 }
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
        if let files, let still {
            ShareLink(
                item: format == .video ? files.video : files.image,
                preview: SharePreview("My world", image: Image(decorative: still, scale: 1))
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.capsule(.accent))
            .transition(.opacity)
        } else {
            Button {} label: {
                Text(failed ? "Couldn't make the video" : "Making the video…")
            }
            .buttonStyle(.capsule(.subtle))
            .disabled(true)
        }
    }

    private func make() async {
        files = nil
        failed = false
        progress = 0
        do {
            let made = try await StoryFilm.make(content) { progress, frame in
                self.progress = progress
                if let frame { self.frame = frame }
            }
            still = UIImage(contentsOfFile: made.image.path)?.cgImage
            withAnimation(Motion.smooth) { files = made }
        } catch is CancellationError {
            // Closed before it was done: nothing to show.
        } catch {
            failed = true
        }
    }
}

/// A thin bar along the card's bottom while the film is made.
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
