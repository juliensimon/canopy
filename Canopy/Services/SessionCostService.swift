import Foundation

/// Token usage totals from a Claude session.
struct TokenUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var model: String = ""

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var estimatedCost: Double {
        let pricing = ModelPricing.for(model)
        let inputCost = Double(inputTokens) * pricing.input / 1_000_000
        let outputCost = Double(outputTokens) * pricing.output / 1_000_000
        let cacheWriteCost = Double(cacheCreationTokens) * pricing.cacheWrite / 1_000_000
        let cacheReadCost = Double(cacheReadTokens) * pricing.cacheRead / 1_000_000
        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }

    var formattedCost: String {
        String(format: "$%.2f", estimatedCost)
    }

    var formattedTokens: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
    }
}

private struct ModelPricing {
    let input: Double
    let output: Double
    let cacheWrite: Double
    let cacheRead: Double

    static func `for`(_ model: String) -> ModelPricing {
        if model.contains("opus") {
            return ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50)
        } else if model.contains("haiku") {
            return ModelPricing(input: 0.80, output: 4, cacheWrite: 1.0, cacheRead: 0.08)
        } else {
            return ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.30)
        }
    }
}

enum SessionCostService {
    static func parseTokenUsage(from jsonlContent: String) -> TokenUsage {
        var usage = TokenUsage()
        for line in jsonlContent.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else {
                continue
            }
            usage.inputTokens += usageDict["input_tokens"] as? Int ?? 0
            usage.outputTokens += usageDict["output_tokens"] as? Int ?? 0
            usage.cacheCreationTokens += usageDict["cache_creation_input_tokens"] as? Int ?? 0
            usage.cacheReadTokens += usageDict["cache_read_input_tokens"] as? Int ?? 0
            if usage.model.isEmpty, let model = message["model"] as? String {
                usage.model = model
            }
        }
        return usage
    }

    static func claudeProjectDir(for directory: String) -> String {
        let expanded = (directory as NSString).expandingTildeInPath
        let resolved = (expanded as NSString).resolvingSymlinksInPath
        let encoded = resolved
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let home = NSHomeDirectory()
        return "\(home)/.claude/projects/\(encoded)"
    }

    static func loadUsage(for workingDirectory: String) -> TokenUsage {
        let projectDir = claudeProjectDir(for: workingDirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectDir) else { return TokenUsage() }

        do {
            let files = try fm.contentsOfDirectory(atPath: projectDir)
            let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }

            var total = TokenUsage()
            for file in jsonlFiles {
                let path = (projectDir as NSString).appendingPathComponent(file)
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                let fileUsage = parseTokenUsage(from: content)
                total.inputTokens += fileUsage.inputTokens
                total.outputTokens += fileUsage.outputTokens
                total.cacheCreationTokens += fileUsage.cacheCreationTokens
                total.cacheReadTokens += fileUsage.cacheReadTokens
                if total.model.isEmpty { total.model = fileUsage.model }
            }
            return total
        } catch {
            return TokenUsage()
        }
    }
}
