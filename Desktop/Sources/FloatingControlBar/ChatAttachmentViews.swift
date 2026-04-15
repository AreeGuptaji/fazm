import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared Attachment Helper

/// Utility methods for file attachment handling, shared across input views.
enum ChatAttachmentHelper {

    /// Add files from URLs to the pending attachments array. Accepts ALL file types;
    /// the model decides what it can handle.
    static func addFiles(from urls: [URL], to attachments: inout [ChatAttachment]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let name = url.lastPathComponent
            let mimeType = mimeTypeForExtension(ext)

            // Generate thumbnail for images
            var thumbnailData: Data?
            if mimeType.hasPrefix("image/") {
                if let image = NSImage(contentsOf: url) {
                    thumbnailData = generateThumbnail(from: image, maxSize: 80)
                }
            }

            let attachment = ChatAttachment(
                path: url.path,
                name: name,
                mimeType: mimeType,
                thumbnailData: thumbnailData
            )
            attachments.append(attachment)
        }
    }

    /// Add a pasted image (raw data) to pending attachments.
    static func addPastedImage(_ data: Data, to attachments: inout [ChatAttachment]) {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "paste-\(UUID().uuidString.prefix(8)).png"
        let tempURL = tempDir.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        var thumbnail: Data?
        if let img = NSImage(data: data) {
            thumbnail = generateThumbnail(from: img, maxSize: 80)
        }
        let att = ChatAttachment(
            path: tempURL.path,
            name: filename,
            mimeType: "image/png",
            thumbnailData: thumbnail
        )
        attachments.append(att)
    }

    /// Open the system file picker. No file type restrictions.
    static func openFilePicker(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // No allowedContentTypes restriction: accept all files
        panel.begin { response in
            if response == .OK {
                completion(panel.urls)
            }
        }
    }

    static func mimeTypeForExtension(_ ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        case "pdf": return "application/pdf"
        case "txt", "md", "csv", "log": return "text/plain"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js", "ts", "tsx", "jsx": return "text/plain"
        case "py", "rs", "swift", "go", "java", "c", "cpp", "h", "hpp", "rb", "sh",
             "yaml", "yml", "toml", "ini", "cfg", "sql", "r", "m", "mm": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    static func generateThumbnail(from image: NSImage, maxSize: CGFloat) -> Data? {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        guard let tiffData = newImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}

// MARK: - Reusable Attachment Button

/// Plus button to open the file picker.
struct ChatAttachmentButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle")
                .scaledFont(size: 18)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Attach files")
    }
}

// MARK: - Reusable Attachment Strip

/// Horizontal scrolling strip of attachment thumbnails with remove buttons.
struct ChatAttachmentStrip: View {
    @Binding var attachments: [ChatAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func attachmentThumbnail(_ attachment: ChatAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbData = attachment.thumbnailData, let nsImage = NSImage(data: thumbData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipped()
                } else if attachment.isPDF {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                        Image(systemName: "doc.fill")
                            .scaledFont(size: 20)
                            .foregroundColor(.red)
                    }
                    .frame(width: 48, height: 48)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                        Image(systemName: "doc.text.fill")
                            .scaledFont(size: 20)
                            .foregroundColor(.blue)
                    }
                    .frame(width: 48, height: 48)
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(FazmColors.overlayForeground.opacity(0.15), lineWidth: 1)
            )

            // Remove button
            Button(action: {
                attachments.removeAll { $0.id == attachment.id }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(size: 14)
                    .foregroundColor(.secondary)
                    .background(Circle().fill(FazmColors.backgroundPrimary).frame(width: 12, height: 12))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .help(attachment.name)
    }
}

// MARK: - Drag & Drop Overlay

/// Full-area overlay shown when files are being dragged over the chat area.
struct ChatDragOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(FazmColors.purplePrimary.opacity(0.08))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(FazmColors.purplePrimary, lineWidth: 2)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 28))
                    .foregroundColor(FazmColors.purplePrimary)
                Text("Drop files here")
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundColor(FazmColors.purplePrimary)
            }
        }
    }
}
