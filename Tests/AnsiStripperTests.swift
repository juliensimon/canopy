import Testing
@testable import Tempo

/// Tests for AnsiStripper — ANSI escape sequence removal.
@Suite("AnsiStripper")
struct AnsiStripperTests {

    // MARK: - Basic

    @Test func plainTextPassesThrough() {
        #expect(AnsiStripper.strip("hello world") == "hello world")
    }

    @Test func emptyString() {
        #expect(AnsiStripper.strip("") == "")
    }

    // MARK: - SGR Colors and Formatting

    @Test func stripsBoldText() {
        #expect(AnsiStripper.strip("\u{1B}[1mBold Text\u{1B}[0m") == "Bold Text")
    }

    @Test func stripsColoredText() {
        #expect(AnsiStripper.strip("\u{1B}[31mRed\u{1B}[0m Normal") == "Red Normal")
    }

    @Test func strips256ColorCodes() {
        #expect(AnsiStripper.strip("\u{1B}[38;5;196mColored\u{1B}[0m") == "Colored")
    }

    @Test func stripsTrueColorCodes() {
        #expect(AnsiStripper.strip("\u{1B}[38;2;255;100;0mTrueColor\u{1B}[0m") == "TrueColor")
    }

    @Test func stripsMultipleFormattingCodes() {
        #expect(AnsiStripper.strip("\u{1B}[1;31;4mFormatted\u{1B}[0m") == "Formatted")
    }

    // MARK: - CSI Sequences

    @Test func stripsCursorMovement() {
        #expect(AnsiStripper.strip("\u{1B}[H\u{1B}[2JHello") == "Hello")
    }

    @Test func stripsCursorPositioning() {
        #expect(AnsiStripper.strip("\u{1B}[10;5HText") == "Text")
    }

    @Test func stripsEraseSequences() {
        #expect(AnsiStripper.strip("Hello\u{1B}[K World") == "Hello World")
    }

    // MARK: - OSC Sequences

    @Test func stripsWindowTitle() {
        #expect(AnsiStripper.strip("\u{1B}]0;My Terminal\u{7}prompt$ ") == "prompt$ ")
    }

    @Test func stripsOscWithST() {
        #expect(AnsiStripper.strip("\u{1B}]0;Title\u{1B}\\content") == "content")
    }

    @Test func stripsHyperlinks() {
        let input = "\u{1B}]8;;https://example.com\u{7}click here\u{1B}]8;;\u{7}"
        #expect(AnsiStripper.strip(input) == "click here")
    }

    // MARK: - Control Characters

    @Test func stripsCarriageReturn() {
        #expect(AnsiStripper.strip("hello\rworld") == "helloworld")
    }

    @Test func stripsBell() {
        #expect(AnsiStripper.strip("alert\u{7}!") == "alert!")
    }

    @Test func handlesBackspace() {
        #expect(AnsiStripper.strip("abc\u{8}d") == "abd")
    }

    @Test func preservesNewlines() {
        #expect(AnsiStripper.strip("line1\nline2\n") == "line1\nline2\n")
    }

    @Test func preservesTabs() {
        #expect(AnsiStripper.strip("col1\tcol2") == "col1\tcol2")
    }

    // MARK: - Real-World Claude Code Output

    @Test func claudePermissionPrompt() {
        let input = "\u{1B}[1;33m?\u{1B}[0m Allow \u{1B}[1mRead\u{1B}[0m tool? \u{1B}[2m(y/n)\u{1B}[0m"
        #expect(AnsiStripper.strip(input) == "? Allow Read tool? (y/n)")
    }

    @Test func claudeToolUseOutput() {
        let input = "\u{1B}[36m⏺\u{1B}[0m \u{1B}[1mUsing tool:\u{1B}[0m Read file.txt"
        #expect(AnsiStripper.strip(input) == "⏺ Using tool: Read file.txt")
    }

    @Test func mixedSequencesAndText() {
        let input = "\u{1B}[32m✓\u{1B}[0m Step 1\n\u{1B}[32m✓\u{1B}[0m Step 2\n\u{1B}[33m⧗\u{1B}[0m Step 3"
        #expect(AnsiStripper.strip(input) == "✓ Step 1\n✓ Step 2\n⧗ Step 3")
    }

    // MARK: - Normalize

    @Test func stripAndNormalize() {
        #expect(AnsiStripper.stripAndNormalize("line1\n\n\n\nline2\n\n\nline3") == "line1\n\nline2\n\nline3")
    }

    @Test func normalizeWithAnsi() {
        let input = "\u{1B}[1mHeader\u{1B}[0m\n\n\n\n\u{1B}[32mContent\u{1B}[0m"
        #expect(AnsiStripper.stripAndNormalize(input) == "Header\n\nContent")
    }

    // MARK: - Edge Cases

    @Test func truncatedEscapeAtEnd() {
        #expect(AnsiStripper.strip("text\u{1B}") == "text")
    }

    @Test func truncatedCSIAtEnd() {
        #expect(AnsiStripper.strip("text\u{1B}[") == "text")
    }

    @Test func unicodePreserved() {
        #expect(AnsiStripper.strip("\u{1B}[1m日本語\u{1B}[0m and émojis 🎉") == "日本語 and émojis 🎉")
    }

    @Test func multipleBackspaces() {
        #expect(AnsiStripper.strip("abc\u{8}\u{8}\u{8}xyz") == "xyz")
    }

    @Test func backspaceOnEmptyString() {
        #expect(AnsiStripper.strip("\u{8}hello") == "hello")
    }

    @Test func charsetDesignation() {
        #expect(AnsiStripper.strip("\u{1B}(BText") == "Text")
    }
}
