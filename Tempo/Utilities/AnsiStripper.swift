import Foundation

/// Strips ANSI escape sequences from terminal output to get plain text.
///
/// Terminal output is full of escape codes for colors, cursor movement,
/// text formatting, etc. The watchdog system needs plain text to match
/// patterns against Claude's output. This stripper handles:
/// - CSI sequences: ESC [ ... (letter)  (colors, cursor, erase)
/// - OSC sequences: ESC ] ... (BEL or ST)  (title, hyperlinks)
/// - Simple escapes: ESC (letter)  (cursor save/restore)
/// - Control chars: \r, \b, BEL, etc.
enum AnsiStripper {

    /// Strips all ANSI escape sequences from the input string.
    static func strip(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)

        var iterator = input.unicodeScalars.makeIterator()

        while let scalar = iterator.next() {
            if scalar == "\u{1B}" {
                // ESC — start of an escape sequence
                guard let next = iterator.next() else { break }

                if next == "[" {
                    // CSI sequence: ESC [ (params) (letter)
                    skipCSI(&iterator)
                } else if next == "]" {
                    // OSC sequence: ESC ] ... (BEL or ESC \)
                    skipOSC(&iterator)
                } else if next == "(" || next == ")" {
                    // Character set designation: ESC ( X or ESC ) X
                    _ = iterator.next() // skip the charset identifier
                } else {
                    // Simple escape: ESC (letter) — just skip the letter
                }
            } else if scalar == "\r" {
                // Carriage return — skip (we keep \n for line breaks)
            } else if scalar == "\u{7}" {
                // BEL — skip
            } else if scalar == "\u{8}" {
                // Backspace — remove last character if present
                if !result.isEmpty {
                    result.removeLast()
                }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }

    /// Strips ANSI and also collapses multiple blank lines into one.
    static func stripAndNormalize(_ input: String) -> String {
        let stripped = strip(input)
        // Collapse runs of blank lines
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [Substring] = []
        var lastWasBlank = false
        for line in lines {
            let isBlank = line.allSatisfy(\.isWhitespace)
            if isBlank {
                if !lastWasBlank {
                    result.append("")
                }
                lastWasBlank = true
            } else {
                result.append(line)
                lastWasBlank = false
            }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Private

    /// Skip a CSI sequence: everything between ESC[ and the terminating letter.
    /// CSI params are digits, semicolons, and intermediate bytes (0x20-0x2F).
    /// The terminator is a byte in range 0x40-0x7E.
    private static func skipCSI(_ iterator: inout String.UnicodeScalarView.Iterator) {
        while let scalar = iterator.next() {
            let value = scalar.value
            // Final byte of CSI sequence: 0x40-0x7E (@ through ~)
            if value >= 0x40 && value <= 0x7E {
                return
            }
        }
    }

    /// Skip an OSC sequence: everything between ESC] and either BEL or ST (ESC \).
    private static func skipOSC(_ iterator: inout String.UnicodeScalarView.Iterator) {
        while let scalar = iterator.next() {
            if scalar == "\u{7}" {
                // BEL terminates OSC
                return
            } else if scalar == "\u{1B}" {
                // Check for ST (ESC \)
                if let next = iterator.next(), next == "\\" {
                    return
                }
            }
        }
    }
}
