import SwiftUI

/// 导入书籍的完整呈现:fileImporter + 导入中转圈 + 失败 alert。
/// Home 的 "Add New Book" 与 Library 菜单共用;导入逻辑本体在 Services/BookImporter。
struct ImportBookModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false
    @State private var importError: Error?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: BookImporter.supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                Task {
                    isImporting = true
                    defer { isImporting = false }
                    do {
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            _ = try await BookImporter.importBook(from: url, modelContext: modelContext)
                        case .failure(let error):
                            throw error
                        }
                    } catch {
                        importError = error
                    }
                }
            }
            .overlay {
                if isImporting {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 160, height: 120)
                        .overlay {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Importing...")
                                    .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                            }
                        }
                }
            }
            .alert(alertTitle, isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError?.localizedDescription ?? "Unknown error")
            }
    }
}

extension View {
    func bookImportPresentation(isPresented: Binding<Bool>) -> some View {
        modifier(ImportBookModifier(isPresented: isPresented))
    }
}

private extension ImportBookModifier {
    /// 重复导入不是失败，别用 "Import Failed" 吓用户。
    var alertTitle: String {
        if case .duplicate = importError as? BookImporter.ImportError {
            return "Already in Library"
        }
        return "Import Failed"
    }
}
