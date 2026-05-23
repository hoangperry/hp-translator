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

    // MARK: - v0.8.5 multi-variant

    @Test("Single-variant init wraps the translated string")
    func singleVariantBackcompat() {
        let m = PreviewHUDViewModel(
            original: "hi",
            translated: "xin chào",
            persona: .japaneseBusiness
        )
        #expect(m.variants == ["xin chào"])
        #expect(m.isMultiVariant == false)
        #expect(m.selectedIndex == 0)
        #expect(m.editableTranslation == "xin chào")
    }

    @Test("isMultiVariant flips on for ≥2 variants")
    func isMultiVariantFlag() {
        let one = PreviewHUDViewModel(
            original: "x",
            variants: ["a"],
            persona: .japaneseBusiness
        )
        let three = PreviewHUDViewModel(
            original: "x",
            variants: ["a", "b", "c"],
            persona: .japaneseBusiness
        )
        #expect(one.isMultiVariant == false)
        #expect(three.isMultiVariant == true)
    }

    @Test("selectNext / selectPrevious wrap around the list")
    func navigationWraps() {
        let m = PreviewHUDViewModel(
            original: "x",
            variants: ["a", "b", "c"],
            persona: .japaneseBusiness
        )
        m.selectNext(); #expect(m.selectedIndex == 1)
        m.selectNext(); #expect(m.selectedIndex == 2)
        m.selectNext(); #expect(m.selectedIndex == 0)   // wrap
        m.selectPrevious(); #expect(m.selectedIndex == 2)  // wrap back
    }

    @Test("selectIndex bounds-checks + drops out of edit mode")
    func selectIndexBounds() {
        let m = PreviewHUDViewModel(
            original: "x",
            variants: ["a", "b", "c"],
            persona: .japaneseBusiness
        )
        m.enterEditMode()
        m.selectIndex(99) // ignored
        #expect(m.selectedIndex == 0)
        #expect(m.isEditing == true)   // not changed by an ignored call

        m.selectIndex(2)
        #expect(m.selectedIndex == 2)
        #expect(m.isEditing == false)  // paging clears edit mode
    }

    @Test("Edits persist per-variant when paging")
    func editsArePerVariant() {
        let m = PreviewHUDViewModel(
            original: "x",
            variants: ["a", "b", "c"],
            persona: .japaneseBusiness
        )
        m.editableTranslation = "A!"
        m.selectIndex(2)
        m.editableTranslation = "C!"
        m.selectIndex(0)
        #expect(m.editableTranslation == "A!")
        m.selectIndex(2)
        #expect(m.editableTranslation == "C!")
        m.selectIndex(1)
        #expect(m.editableTranslation == "b")   // untouched
    }

    @Test("Single-variant nav is a no-op")
    func singleVariantNavNoOp() {
        let m = PreviewHUDViewModel(
            original: "x",
            variants: ["a"],
            persona: .japaneseBusiness
        )
        m.selectNext()
        m.selectPrevious()
        #expect(m.selectedIndex == 0)
    }
}

@Suite("RewriteResultProcessor — multi-variant parser")
struct VariantSplitterTests {
    @Test("Splits on the canonical sentinel")
    func splitsOnSentinel() {
        let raw = """
        Em xin lỗi anh, để em kiểm tra lại nhé.
        ---VARIANT---
        Anh ơi, em check lại giúp mình ngay đây ạ.
        ---VARIANT---
        Cảm phiền anh chút, em rà lại đơn rồi báo lại nhé.
        """
        let out = RewriteResultProcessor.splitVariants(raw)
        #expect(out.count == 3)
        #expect(out[0].hasPrefix("Em xin lỗi anh"))
        #expect(out[2].hasSuffix("nhé."))
    }

    @Test("Falls back to numbered-list when sentinel absent")
    func fallbackNumberedList() {
        let raw = """
        1. Em sẽ xử lý ngay anh ạ.
        2. Anh ơi, để em xử lý liền nhé.
        3. Em xin phép giải quyết phần này luôn ạ.
        """
        let out = RewriteResultProcessor.splitVariants(raw)
        #expect(out.count == 3)
        #expect(out[0].contains("xử lý ngay"))
        #expect(!out[0].hasPrefix("1."))   // marker stripped
    }

    @Test("Dedupes identical variants while preserving order")
    func dedupes() {
        let raw = """
        Cảm ơn anh.
        ---VARIANT---
        Cảm ơn anh.
        ---VARIANT---
        Cảm ơn anh nhé.
        """
        let out = RewriteResultProcessor.splitVariants(raw)
        #expect(out == ["Cảm ơn anh.", "Cảm ơn anh nhé."])
    }

    @Test("Drops empty + refusal chunks")
    func dropsRefusals() {
        let raw = """
        I cannot help with that.
        ---VARIANT---
        Em xin lỗi anh ạ.
        ---VARIANT---

        ---VARIANT---
        Anh ơi để em xử lý nhé.
        """
        let out = RewriteResultProcessor.splitVariants(raw)
        #expect(out == ["Em xin lỗi anh ạ.", "Anh ơi để em xử lý nhé."])
    }

    @Test("Single chunk with no sentinel or numbering returns one variant")
    func singleChunkUntouched() {
        let raw = "Em xử lý giúp anh ngay đây ạ."
        let out = RewriteResultProcessor.splitVariants(raw)
        #expect(out == ["Em xử lý giúp anh ngay đây ạ."])
    }
}

@Suite("TranslationStyle.withVariantCount")
struct VariantStyleTests {
    @Test("withVariantCount returns a copy with the new count, preserving everything else")
    func withVariantCountCopies() {
        let original = TranslationStyle(
            direction: .rewrite,
            targetLanguage: "vi",
            register: .neutral,
            customStyleInstruction: "polite",
            displayLabelOverride: "Polite rewrite",
            allowsExpressiveContent: false
        )
        let three = original.withVariantCount(3)
        #expect(three.variantCount == 3)
        #expect(three.direction == .rewrite)
        #expect(three.targetLanguage == "vi")
        #expect(three.register == .neutral)
        #expect(three.customStyleInstruction == "polite")
        #expect(three.displayLabelOverride == "Polite rewrite")
        #expect(three.allowsExpressiveContent == false)
        // Original is unchanged.
        #expect(original.variantCount == 1)
    }

    @Test("variantCount clamps to [1, 5]")
    func variantCountClamps() {
        let zero = TranslationStyle(
            direction: .rewrite, targetLanguage: "en", register: .neutral,
            variantCount: 0
        )
        let huge = TranslationStyle(
            direction: .rewrite, targetLanguage: "en", register: .neutral,
            variantCount: 99
        )
        #expect(zero.variantCount == 1)
        #expect(huge.variantCount == 5)
    }
}
