import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct RootView: View {
    @StateObject private var camera = CameraService()
    @AppStorage("hasSeenFirstRunGuide") private var hasSeenFirstRunGuide = false
    @State private var showGuide = false

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showPhotosPicker = false
    @State private var inspectorImage: InspectorImage?

    var body: some View {
        ZStack {
            backdrop

            switch camera.authState {
            case .authorized:
                liveView
            case .denied:
                fallbackView(reason: .denied)
            case .unavailable:
                fallbackView(reason: .noCamera)
            case .unknown:
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            camera.requestAccessAndStart()
            if !hasSeenFirstRunGuide { showGuide = true }
        }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showGuide, onDismiss: { hasSeenFirstRunGuide = true }) {
            FirstRunGuideView()
        }
        .fullScreenCover(item: $inspectorImage) { wrapper in
            PhotoInspectorView(image: wrapper.image)
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    inspectorImage = InspectorImage(image: ui)
                }
                photoPickerItem = nil
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                    inspectorImage = InspectorImage(image: ui)
                }
            }
        }
    }

    // MARK: - Backdrop
    /// A soft gradient so the screen never reads as pure black when the
    /// camera preview is empty (simulator, denied, briefly during startup).
    /// Pure black + a tiny reticle made the original UI feel broken.
    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.14),
                Color(red: 0.04, green: 0.04, blue: 0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Live camera
    private var liveView: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .onTapGesture {
                    camera.isFrozen.toggle()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

            Reticle()
                .frame(width: 84, height: 84)
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.5), radius: 6)

            VStack(spacing: 0) {
                topBar
                Spacer()
                ColorReadoutView(
                    match: camera.currentMatch,
                    sampledColor: Color(.sRGB,
                                        red: camera.sampledRed,
                                        green: camera.sampledGreen,
                                        blue: camera.sampledBlue,
                                        opacity: 1),
                    isFrozen: camera.isFrozen
                )
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 10) {
            Spacer()
            loadMenu
            iconButton(systemName: "questionmark") {
                showGuide = true
            }
            .accessibilityLabel(Text("Help"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var loadMenu: some View {
        Menu {
            Button {
                showPhotosPicker = true
            } label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }
        } label: {
            iconButtonLabel(systemName: "photo.on.rectangle.angled")
        }
        .accessibilityLabel(Text("Load a photo"))
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            iconButtonLabel(systemName: systemName)
        }
    }

    private func iconButtonLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }

    // MARK: - Fallback (no camera available, or denied)
    private enum FallbackReason { case denied, noCamera }

    @ViewBuilder
    private func fallbackView(reason: FallbackReason) -> some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: reason == .denied ? "camera.metering.unknown" : "camera.on.rectangle")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.85))
                Text(reason == .denied ? "Camera access needed" : "No camera available")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(reason == .denied
                     ? String(localized: "I Can See! needs camera access to identify colors. You can also load a photo to inspect.")
                     : String(localized: "This device doesn't have a usable camera, but you can still load a photo to inspect."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button {
                    showPhotosPicker = true
                } label: {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Choose from Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)

                if reason == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote)
                    .tint(.white.opacity(0.7))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                showGuide = true
            } label: {
                Label("How it works", systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.bottom, 24)
        }
    }
}

/// Crosshair drawn over the camera preview. Two-tone (black halo + white
/// core) so it stays visible against any background.
private struct Reticle: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(.black.opacity(0.7), lineWidth: 5)
            Circle().strokeBorder(.white, lineWidth: 2.5)
            Rectangle().fill(.white).frame(width: 1.5, height: 22)
            Rectangle().fill(.white).frame(width: 22, height: 1.5)
            Rectangle().fill(.black.opacity(0.6)).frame(width: 0.5, height: 22)
            Rectangle().fill(.black.opacity(0.6)).frame(width: 22, height: 0.5)
        }
    }
}

/// Wraps a `UIImage` so it can drive `.fullScreenCover(item:)` without
/// retroactively conforming `UIImage` itself to `Identifiable` — UIKit may
/// add that conformance in a future SDK and a retroactive one would clash.
private struct InspectorImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview { RootView() }
