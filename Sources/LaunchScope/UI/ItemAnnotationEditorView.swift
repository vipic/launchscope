import SwiftUI

struct ItemAnnotationEditorView: View {
    var item: StartupItem
    var onSave: (String, [String], Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var tagsText: String
    @State private var isTrusted: Bool

    init(item: StartupItem, annotation: ItemAnnotation?, onSave: @escaping (String, [String], Bool) -> Void) {
        self.item = item
        self.onSave = onSave
        _note = State(initialValue: annotation?.note ?? "")
        _tagsText = State(initialValue: annotation?.tags.joined(separator: ", ") ?? "")
        _isTrusted = State(initialValue: annotation?.isTrusted ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("备注与信任名单").font(.title2.bold())
            Text(item.displayName).foregroundStyle(.secondary)
            Toggle("信任此项目", isOn: $isTrusted)
            TextField("标签（使用逗号分隔）", text: $tagsText)
            TextEditor(text: $note).frame(minHeight: 130).overlay {
                RoundedRectangle(cornerRadius: 6).stroke(.separator)
            }
            Text("这里只保存来源与标识组成的脱敏键，不保存启动路径或配置内容。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let tags = tagsText.split(separator: ",").map(String.init)
                    onSave(note, tags, isTrusted)
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }.padding(22).frame(width: 520)
    }
}
