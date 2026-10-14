// WP15: the Welcome window controller's decisions (first launch, visual QA, the close button, activation
// hand-back) and the onboarding QA launch arguments.
import CrannyOnboarding
import Testing
@testable import CrannyAppShell

@Suite struct WelcomeWindowPolicyTests {
    @Test func theWelcomeShowsOnlyOnTheFirstLaunch() {
        typealias Policy = WelcomeWindowPolicy
        #expect(Policy.launch(completedVersion: nil, qaWelcomeStep: nil, qaTutorialStep: nil, isVisualQA: false) == .welcome(.hello))
        #expect(Policy.launch(completedVersion: "0.1.0", qaWelcomeStep: nil, qaTutorialStep: nil, isVisualQA: false) == .nothing)
    }

    @Test func visualQAShowsExactlyWhatItAsksFor() {
        typealias Policy = WelcomeWindowPolicy
        // Any --qa-* run (here --qa-state) never gets the first-launch welcome on top of what it forces.
        #expect(Policy.launch(completedVersion: nil, qaWelcomeStep: nil, qaTutorialStep: nil, isVisualQA: true) == .nothing)
        #expect(Policy.launch(completedVersion: "0.1.0", qaWelcomeStep: "permissions", qaTutorialStep: nil, isVisualQA: true)
                == .welcome(.permissions))
        #expect(Policy.launch(completedVersion: nil, qaWelcomeStep: "sideways", qaTutorialStep: nil, isVisualQA: true)
                == .welcome(.hello))                                           // unknown step names start at step 1
        #expect(Policy.launch(completedVersion: nil, qaWelcomeStep: nil, qaTutorialStep: 4, isVisualQA: true) == .tutorial(step: 4))
    }

    @Test func theCloseButtonCountsAsSkipExceptInVisualQA() {
        #expect(WelcomeWindowPolicy.recordsCompletionOnClose(hasFinished: false, isVisualQA: false))
        #expect(!WelcomeWindowPolicy.recordsCompletionOnClose(hasFinished: true, isVisualQA: false))   // the outcome recorded it
        #expect(!WelcomeWindowPolicy.recordsCompletionOnClose(hasFinished: false, isVisualQA: true))
    }

    @Test func activationGoesBackOnlyWhileCrannyIsActive() {
        #expect(WelcomeWindowPolicy.handsBackActivation(isActive: true, previousAppIsRunning: true))
        #expect(!WelcomeWindowPolicy.handsBackActivation(isActive: false, previousAppIsRunning: true))  // never steal focus
        #expect(!WelcomeWindowPolicy.handsBackActivation(isActive: true, previousAppIsRunning: false))
    }
}

#if DEBUG
@Test func onboardingQAArgumentsParse() {
    let welcome = QAHooks.Options(arguments: ["Cranny", "--qa-welcome", "preset", "--qa-snapshot", "/tmp/qa"])
    #expect(welcome == QAHooks.Options(welcomeStep: "preset", snapshotPath: "/tmp/qa"))
    #expect(!welcome.isEmpty)
    let tour = QAHooks.Options(arguments: ["Cranny", "--qa-tutorial", "3", "--qa-exit-after", "30"])
    #expect(tour == QAHooks.Options(exitAfter: 30, tutorialStep: 3))
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-tutorial", "0"]).tutorialStep == nil)      // 1-based
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-tutorial", "two"]).tutorialStep == nil)
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-snapshot", "/tmp/qa"]).isEmpty)           // a snapshot alone forces nothing
}
#endif
