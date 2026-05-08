import Testing

@testable import ContextualMacTranslator

@Suite("Preview HUD")
@MainActor
struct PreviewHUDTests {
    @Test("Tab/edit action switches translation into edit mode")
    func enterEditMode() {
        let model = PreviewHUDViewModel(
            original: "xin chao",
            translated: "こんにちは",
            persona: .japaneseBusiness
        )

        #expect(model.isEditing == false)
        model.enterEditMode()
        #expect(model.isEditing == true)
    }

    @Test("send returns the edited translation")
    func sendUsesEditedTranslation() {
        let model = PreviewHUDViewModel(
            original: "xin chao",
            translated: "こんにちは",
            persona: .japaneseBusiness
        )
        var sent = ""
        model.onSend = { sent = model.editableTranslation }

        model.editableTranslation = "お疲れ様です。"
        model.onSend()

        #expect(sent == "お疲れ様です。")
    }
}
