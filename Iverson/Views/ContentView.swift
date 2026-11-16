/// Main view for iverson.io.

import SwiftUI
import Speech

struct ContentView: View {
    @State private var story: Story = Story.blank()
    @State private var sessionID = UUID()
    /// Owned here so session remounts of TranscriptView do not recreate CoreBluetooth.
    @State private var keyboard = BluetoothKeyboardPeripheral()

    var body: some View {
        TranscriptView(story: $story, keyboard: keyboard) {
            withAnimation(.easeInOut(duration: 0.45)) {
                story = Story.blank()
                sessionID = UUID()
            }
        }
        .id(sessionID)
        .preferredColorScheme(.light)
    }
}
