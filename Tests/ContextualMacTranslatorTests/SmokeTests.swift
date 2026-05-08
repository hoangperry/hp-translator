import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test("Test target builds and runs")
    func smoke() {
        #expect(1 + 1 == 2)
    }
}
