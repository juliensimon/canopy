import Testing
@testable import Tempo

/// Additional edge case tests for AnsiStripper.
@Suite("AnsiStripper Edge Cases")
struct AnsiStripperEdgeCaseTests {

    // MARK: - Empty/Minimal Sequences

    @Test func emptyResetSequence() {
        // ESC[m is equivalent to ESC[0m (reset all)
        #expect(AnsiStripper.strip("\u{1B}[mText") == "Text")
    }

    @Test func csiWithLetterTerminator() {
        // ESC[ followed by 'a' (0x61) — 'a' is a valid CSI terminator
        // so it consumes "a", leaving "fter"
        #expect(AnsiStripper.strip("before\u{1B}[after") == "beforefter")
    }

    @Test func multipleConsecutiveEscapes() {
        let input = "\u{1B}[1m\u{1B}[31m\u{1B}[4mTriple\u{1B}[0m"
        #expect(AnsiStripper.strip(input) == "Triple")
    }

    // MARK: - Mixed Control Characters

    @Test func carriageReturnThenBackspace() {
        // CR is stripped, then backspace removes last char of "hello" → "hell", then "world"
        #expect(AnsiStripper.strip("hello\r\u{8}world") == "hellworld")
    }

    @Test func backspaceAndCarriageReturnMixed() {
        // "abc" then backspace removes 'c', then CR is stripped
        #expect(AnsiStripper.strip("abc\u{8}\rdef") == "abdef")
    }

    @Test func bellInsideText() {
        #expect(AnsiStripper.strip("he\u{7}llo") == "hello")
    }

    // MARK: - Unicode Edge Cases

    @Test func backspaceOnEmoji() {
        // Backspace removes one Swift Character (which may be multi-scalar)
        let result = AnsiStripper.strip("🎉\u{8}x")
        #expect(result == "x")
    }

    @Test func backspaceOnCJK() {
        let result = AnsiStripper.strip("日本\u{8}語")
        #expect(result == "日語")
    }

    @Test func ansiAroundEmoji() {
        let input = "\u{1B}[33m⚡\u{1B}[0m Lightning"
        #expect(AnsiStripper.strip(input) == "⚡ Lightning")
    }

    @Test func fullWidthCharacters() {
        let input = "\u{1B}[1mＨＥＬＬＯ\u{1B}[0m"
        #expect(AnsiStripper.strip(input) == "ＨＥＬＬＯ")
    }

    // MARK: - Real-World Terminal Patterns

    @Test func promptWithColorAndPath() {
        // Typical zsh prompt: user@host ~/path %
        let input = "\u{1B}[32muser\u{1B}[0m@\u{1B}[34mhost\u{1B}[0m \u{1B}[36m~/dev\u{1B}[0m % "
        #expect(AnsiStripper.strip(input) == "user@host ~/dev % ")
    }

    @Test func lsColorOutput() {
        // Typical `ls --color` output
        let input = "\u{1B}[0m\u{1B}[01;34mdir1\u{1B}[0m  \u{1B}[01;32mscript.sh\u{1B}[0m  file.txt"
        #expect(AnsiStripper.strip(input) == "dir1  script.sh  file.txt")
    }

    @Test func gitDiffHeader() {
        let input = "\u{1B}[1mdiff --git a/file.txt b/file.txt\u{1B}[m"
        #expect(AnsiStripper.strip(input) == "diff --git a/file.txt b/file.txt")
    }

    @Test func progressBar() {
        // Progress bars often use \r to overwrite the line
        let input = "Downloading... 50%\rDownloading... 100%\n"
        #expect(AnsiStripper.strip(input) == "Downloading... 50%Downloading... 100%\n")
    }

    @Test func cursorSaveRestore() {
        // ESC7 = save cursor, ESC8 = restore cursor
        let input = "\u{1B}7Saved\u{1B}8Restored"
        #expect(AnsiStripper.strip(input) == "SavedRestored")
    }

    // MARK: - Long Input

    @Test func longStringPerformance() {
        // 10K characters with ANSI codes sprinkled in
        var input = ""
        for i in 0..<1000 {
            input += "\u{1B}[31mline \(i)\u{1B}[0m\n"
        }
        let result = AnsiStripper.strip(input)
        #expect(result.contains("line 0"))
        #expect(result.contains("line 999"))
        #expect(!result.contains("\u{1B}"))
    }

    // MARK: - Normalize Edge Cases

    @Test func normalizeOnlyBlankLines() {
        // All blank lines collapse into a single blank line entry (empty string)
        let result = AnsiStripper.stripAndNormalize("\n\n\n\n")
        #expect(result == "")
    }

    @Test func normalizePreservesSingleNewline() {
        let result = AnsiStripper.stripAndNormalize("a\nb")
        #expect(result == "a\nb")
    }

    @Test func normalizeWithTrailingBlanks() {
        let result = AnsiStripper.stripAndNormalize("content\n\n\n")
        #expect(result == "content\n")
    }
}
