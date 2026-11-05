#!/bin/bash
# Checks that every saved meeting.json still decodes with the current Meeting model, and that merging
# speakers works on a copy in memory. Reads the meetings only; never writes them.
# Usage: scripts/check-meetings-decode.sh [meetings-dir]
set -euo pipefail
cd "$(dirname "$0")/.."

MEETINGS="${1:-$HOME/Library/Application Support/GrokNotes/Meetings}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

var checked = 0, failed = 0
let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let file = dir.appendingPathComponent("meeting.json")
    guard let data = try? Data(contentsOf: file) else { continue }
    checked += 1
    do {
        var m = try decoder.decode(Meeting.self, from: data)
        _ = try decoder.decode(Meeting.self, from: try encoder.encode(m))
        let remote = m.speakerKeys.filter { $0 != Meeting.meKey }
        var note = "\(m.utterances.count) lines, \(m.speakerKeys.count) speakers"
        if remote.count >= 2 {
            let lines = m.utterances.count
            m.mergeSpeaker(remote[1], into: remote[0])
            guard m.utterances.count == lines, !m.speakerKeys.contains(remote[1]), m.aliasedKey(remote[1]) == remote[0] else {
                throw NSError(domain: "merge", code: 1, userInfo: [NSLocalizedDescriptionKey: "merge check failed"])
            }
            _ = try decoder.decode(Meeting.self, from: try encoder.encode(m))
            note += ", merge ok"
        }
        print("ok    \(dir.lastPathComponent)  \(note)")
    } catch {
        failed += 1
        print("FAIL  \(dir.lastPathComponent)  \(error)")
    }
}
print("\(checked) meetings checked, \(failed) failed")
exit(failed == 0 ? 0 : 1)
SWIFT

# The app's own sources, with the driver above as the entry point instead of the app's @main.
mkdir "$WORK/src"
sources=()
while IFS= read -r file; do
    if grep -q '^@main' "$file"; then
        sed '/^@main/d' "$file" > "$WORK/src/$(basename "$file")"
        sources+=("$WORK/src/$(basename "$file")")
    else
        sources+=("$file")
    fi
done < <(find Sources/GrokNotes -name '*.swift')
swiftc -o "$WORK/check" -suppress-warnings "${sources[@]}" "$WORK/main.swift" 2>&1 | grep -v '^$' || true
test -x "$WORK/check"
"$WORK/check" "$MEETINGS"
