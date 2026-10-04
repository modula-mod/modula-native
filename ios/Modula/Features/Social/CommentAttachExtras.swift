import ContactsUI
import PencilKit
import SwiftUI
import VisionKit

// MARK: - Document scanner

struct CommentDocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: CommentDocumentScanner
        init(_ parent: CommentDocumentScanner) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<min(scan.pageCount, 4)).map { scan.imageOfPage(at: $0) })
            parent.dismiss()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}

// MARK: - Sketch (PencilKit)

struct CommentSketchSheet: View {
    var onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var isEmpty = true

    var body: some View {
        NavigationStack {
            CommentCanvas(canvas: canvas, isEmpty: $isEmpty)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(12)
                .navigationTitle("Sketch")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", systemImage: "trash") { canvas.drawing = PKDrawing(); isEmpty = true }
                            .disabled(isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Attach") {
                            let bounds = canvas.drawing.bounds.insetBy(dx: -24, dy: -24)
                            let image = UIGraphicsImageRenderer(bounds: bounds).image { ctx in
                                UIColor.white.setFill()
                                ctx.fill(bounds)
                                canvas.drawing.image(from: bounds, scale: UIScreen.main.scale).draw(in: bounds)
                            }
                            onDone(image)
                            dismiss()
                        }
                        .disabled(isEmpty)
                    }
                }
        }
    }
}

private struct CommentCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    @Binding var isEmpty: Bool
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        let picker = PKToolPicker()
        context.coordinator.picker = picker
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CommentCanvas
        var picker: PKToolPicker?
        init(_ parent: CommentCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let empty = canvasView.drawing.strokes.isEmpty
            if parent.isEmpty != empty { DispatchQueue.main.async { self.parent.isEmpty = empty } }
        }
    }
}

// MARK: - Contact picker (no Contacts permission needed)

struct CommentContactPicker: UIViewControllerRepresentable {
    var onPick: (String) -> Void
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String) -> Void
        init(onPick: @escaping (String) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Contact"
            var parts = ["👤 **\(name)**"]
            if let phone = contact.phoneNumbers.first?.value.stringValue { parts.append("📞 \(phone)") }
            if let email = contact.emailAddresses.first?.value as String? { parts.append("✉️ \(email)") }
            onPick(parts.joined(separator: "\n"))
        }
    }
}

// MARK: - Event

struct CommentEventSheet: View {
    var onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var place = ""
    @State private var allDay = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Event name", text: $title)
                Toggle("All day", isOn: $allDay)
                DatePicker("Starts", selection: $date, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                TextField("Location (optional)", text: $place)
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let when = allDay ? date.formatted(date: .complete, time: .omitted) : date.formatted(date: .abbreviated, time: .shortened)
                        var lines = ["📅 **\(title.trimmingCharacters(in: .whitespaces))**", "🕒 \(when)"]
                        if !place.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("📍 \(place)") }
                        onInsert(lines.joined(separator: "\n"))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
