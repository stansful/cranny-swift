// CrannyOnboarding/Steps/HelloStep.swift — step 1 (DESIGN.md §12.1): the real notch plays the "Hi" while the
// stage mirrors it. One headline, one sentence, and a way to see it again.
import CrannyCore
import Foundation
import SwiftUI

struct HelloStep: View {
    let flow: WelcomeFlow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            StepHeader(title: String(localized: "Look up. That's Cranny.", bundle: .module, comment: "Welcome: headline"),
                       message: String(localized: "Your music, calendar, files and shortcuts live in the notch, one glance away.",
                                       bundle: .module, comment: "Welcome: one sentence about what Cranny does"))
            if !flow.stage.hasNotch {
                Label {
                    Text("On displays without a notch, Cranny floats just under the menu bar.", bundle: .module,
                         comment: "Welcome step 1: note shown on Macs whose display has no camera notch")
                } icon: {
                    Image(systemName: "display")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Button { flow.greetAgain() } label: {
                Label {
                    Text("Say hi again", bundle: .module, comment: "Welcome step 1: replays the greeting on the real notch")
                } icon: {
                    Image(systemName: StageGreeting.symbol)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

#Preview("Step 1 · Hello") {
    WelcomePreview(step: .hello)
}
