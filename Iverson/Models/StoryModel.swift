/// Story data model.

import Foundation
import AVFoundation
import FoundationModels

@Observable
class Story: Identifiable {
    typealias StartTime = CMTime
    
    let id: UUID
    var title: String
    var text: AttributedString
    var url: URL?
    var isDone: Bool
    
    init(title: String, text: AttributedString, url: URL? = nil, isDone: Bool = false) {
        self.title = title
        self.text = text
        self.url = url
        self.isDone = isDone
        self.id = UUID()
    }
    
    func suggestedTitle() async throws -> String? {
        let plain = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        guard SystemLanguageModel.default.isAvailable else {
            return String(plain.prefix(48))
        }
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let answer = try await session.respond(to: "Suggest a very short title for this speech transcript. Return only the title, no quotes or extra text. Transcript: \(plain)")
        return answer.content.trimmingCharacters(in: .punctuationCharacters)
    }
}

extension Story {
    static func blank() -> Story {
        return .init(title: "New Session", text: AttributedString(""))
    }
    
    func storyBrokenUpByLines() -> AttributedString {
        print(String(text.characters))
        if url == nil {
            print("url was nil")
            return text
        } else {
            var final = AttributedString("")
            var working = AttributedString("")
            let copy = text
            copy.runs.forEach { run in
                if copy[run.range].characters.contains(".") {
                    working.append(copy[run.range])
                    final.append(working)
                    final.append(AttributedString("\n\n"))
                    working = AttributedString("")
                } else {
                    if working.characters.isEmpty {
                        let newText = copy[run.range].characters
                        let attributes = run.attributes
                        let trimmed = newText.trimmingPrefix(" ")
                        let newAttributed = AttributedString(trimmed, attributes: attributes)
                        working.append(newAttributed)
                    } else {
                        working.append(copy[run.range])
                    }
                }
            }
            
            if final.characters.isEmpty {
                return working
            }
            
            return final
        }
    }
}
