import SwiftUI

struct AnnotationPopover: View {
    let selectedText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
                .padding(8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("添加批注")
                .font(.headline)

            TextEditor(text: $note)
                .font(.body)
                .frame(minHeight: 80)
                .border(.quaternary)

            HStack {
                Button("取消", role: .cancel, action: onCancel)
                Spacer()
                Button("保存") { onSave(note) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}
