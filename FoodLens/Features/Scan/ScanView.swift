import PhotosUI
import SwiftUI

struct ScanView: View {
    @StateObject private var camera = CameraService()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoLoadError: String?

    var body: some View {
        Group {
            if let image = camera.photo {
                MealResultView(image: image) { camera.retake() }
                    .id(ObjectIdentifier(image))
            } else if camera.permissionDenied || camera.cameraUnavailable {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        camera.permissionDenied ? "Немає доступу до камери" : "Камера недоступна",
                        systemImage: "camera.fill",
                        description: Text(camera.permissionDenied ? "Дозвольте доступ у Налаштуваннях iPhone → FoodLens → Камера або виберіть фото." : "Виберіть фото страви з галереї.")
                    )
                    libraryButton.buttonStyle(.borderedProminent)
                    if let photoLoadError { Text(photoLoadError).font(.caption).foregroundStyle(.orange) }
                }
            } else {
                ZStack(alignment: .bottom) {
                    CameraPreview(session: camera.session).ignoresSafeArea(edges: .bottom)
                    VStack(spacing: 12) {
                        Text("Зніміть всю тарілку зверху")
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                        HStack {
                            libraryButton
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .frame(width: 56, height: 56)
                                .background(.black.opacity(0.45), in: Circle())
                                .foregroundStyle(.white)
                            Spacer()
                            Button { Task { await camera.capture() } } label: {
                                Circle().fill(.white).frame(width: 72, height: 72)
                                    .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 3).padding(5))
                                    .overlay { if camera.isCapturing { ProgressView() } }
                            }
                            .disabled(camera.isCapturing)
                            .accessibilityLabel("Зробити фото")
                            Spacer()
                            Color.clear.frame(width: 56, height: 56)
                        }
                        .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Сканування")
        .navigationBarTitleDisplayMode(.inline)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                defer { selectedPhoto = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    photoLoadError = "Не вдалося відкрити фото."
                    return
                }
                photoLoadError = nil
                camera.show(image)
            }
        }
    }

    private var libraryButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Вибрати фото", systemImage: "photo.on.rectangle")
        }
        .accessibilityLabel("Вибрати фото з галереї")
    }
}
