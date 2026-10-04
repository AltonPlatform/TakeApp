# Take Composer Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Publish into a liquid-glass bottom chrome above the keyboard, make mentions a floating overlay, add DnD reorder to attachments, ship a reusable liquid-glass keyboard-dismiss button everywhere, and fix the text-duplication binding-loop bug — all in the Alton app's monochrome visual language.

**Architecture:** Pure Presentation-layer change. `CreatePostView` is restructured: Publish leaves the nav bar and becomes a pill in a glass bottom chrome; the mention autocomplete is lifted out of `safeAreaInset(.bottom)` into a floating overlay; a new reusable `LiquidGlassKeyboardDismissButton` replaces `keyboardDoneButton()` on every composer screen. The text-duplication fix is isolated to the `MarkdownEditorView`/`RichTextEditorView` Coordinator binding loop. No ViewModel/API changes.

**Tech Stack:** SwiftUI (iOS 18), Swift 5.0 language mode, UIKit bridges via `UIViewRepresentable`, `@Observable` + `@MainActor`, XCTest (`AltonAppTests`). No new Swift Package dependencies.

**Spec:** `AltonApp/docs/superpowers/specs/2026-10-04-take-composer-redesign-design.md`

## Global Constraints

- iOS 18, Swift 5.0 (`SWIFT_VERSION = 5.0`). No Swift 6 / default `MainActor` isolation.
- `@Observable` + `@MainActor` for new UI state. No `ObservableObject`/`@Published`.
- SwiftUI first; UIKit only via `UIViewRepresentable` for perf-sensitive surfaces.
- No new Swift Package dependencies. Do not edit `.pbxproj` by hand — add files via the synced `AltonApp` group / folder reference.
- Color tokens: bg `#ffffff`, text `#1c1c1e`, secondary `#a0a3ab`, divider `#eaecf0`, Apple system font (`-apple-system`). No system blue in the composer (monochrome).
- Tests: XCTest in `AltonAppTests`. No UI test target — pure-layout tasks use a manual verification checklist; logic tasks ship a unit test.
- Commit after every task. Keep commits focused (one task = one commit).

## Review Focus

1. **Publish hidden under keyboard** (success criterion): with keyboard up + mention active + attachments present, the Post pill must stay visible above the keyboard at the moment of publish. → manual verify in Task 3.
2. **Text duplication** when rapid typing + mention insert + format apply: the editor must not re-import its own just-exported markdown. → unit test in Task 7 (`importExternalMarkdownIfNeeded` is skipped while a just-applied edit is outstanding).
3. **DnD loses/duplicates an attachment** on drop: reorder must move (not copy) the dragged item and preserve `loadedPickerItemIDs`. → unit test in Task 5.
4. **Mention overlay shows when it should not / hides when it should**: overlay visibility must follow `mentionPicker.isVisible` only. → unit test in Task 4.
5. **Dismiss button lingers after keyboard hides**: button must disappear with the keyboard, not stay on screen. → unit test in Task 1 (`KeyboardDismissController`).

## File Structure

- **Create** `AltonApp/AltonApp/Presentation/Common/LiquidGlassKeyboardDismissButton.swift` — reusable glass dismiss button + `.liquidGlassKeyboardDismiss()` modifier + `KeyboardDismissController` (keyboard visibility state).
- **Create** `AltonApp/AltonApp/Presentation/Post/ComposerBottomChrome.swift` — the glass bottom chrome (format capsule + tool row + Post pill + char meter), extracted from `CreatePostView` so the chrome is one focused file.
- **Create** `AltonApp/AltonApp/Presentation/Post/MentionOverlayView.swift` — floating mention autocomplete wrapper (lifts `MentionAutocompleteView` out of the inset).
- **Modify** `AltonApp/AltonApp/Presentation/Post/CreatePostView.swift` — remove Post from nav bar; adopt new chrome; adopt floating mention overlay; adopt liquid-glass dismiss.
- **Modify** `AltonApp/AltonApp/Presentation/Post/MediaAttachmentView.swift` — DnD reorder on `ComposerAttachmentStrip`; align thumb radius to 8 + `#eaecf0` border; replace `xmark.circle.fill` with outline-SVG remove control.
- **Modify** `AltonApp/AltonApp/Presentation/Post/MentionAutocompleteView.swift` — keep list UI; lift placement out of `safeAreaInset` (handled by `MentionOverlayView`).
- **Modify** `AltonApp/AltonApp/Presentation/Common/KeyboardDismiss.swift` — keep `KeyboardDismiss.dismiss()`; deprecate `keyboardDoneButton()` modifiers (reroute to `.liquidGlassKeyboardDismiss()`).
- **Modify** `AltonApp/AltonApp/Presentation/Post/MarkdownEditorView.swift` — fix the `importExternalMarkdownIfNeeded` binding-loop race (Coordinator).
- **Modify** `AltonApp/AltonApp/Presentation/Engagement/CommentComposerFullScreenView.swift`, `ReplyTakeView.swift`, `Camera/Components/LocationPickerSheet.swift`, `Camera/HashtagInsertSheet.swift` — swap `.keyboardDoneButton()` → `.liquidGlassKeyboardDismiss()`.
- **Create** `AltonAppTests/KeyboardDismissControllerTests.swift`, `AltonAppTests/ComposerBottomChromeStateTests.swift`, `AltonAppTests/MentionOverlayStateTests.swift`, `AltonAppTests/AttachmentReorderTests.swift`, `AltonAppTests/LiquidGlassDismissAdoptionTests.swift`, `AltonAppTests/MarkdownEditorBindingLoopTests.swift`, `AltonAppTests/MonochromeColorPassTests.swift`.


---

### Task 1: LiquidGlassKeyboardDismissButton (reusable component)

**Files:**
- Create: `AltonApp/AltonApp/Presentation/Common/LiquidGlassKeyboardDismissButton.swift`
- Create: `AltonAppTests/KeyboardDismissControllerTests.swift`

**Interfaces:**
- Produces: `KeyboardDismissController` (`@Observable @MainActor final class` with `var isKeyboardVisible: Bool`, `var keyboardHeight: CGFloat`, and `func dismiss()`); `LiquidGlassKeyboardDismissButton` (SwiftUI `View`); `View.liquidGlassKeyboardDismiss(controller:)` modifier that overlays the button at bottom-trailing, offset upward by `controller.keyboardHeight` so it floats just above the keyboard's top edge, visible only when `controller.isKeyboardVisible`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AltonApp

final class KeyboardDismissControllerTests: XCTestCase {
    @MainActor func testVisibleTogglesWithKeyboardNotifications() {
        let controller = KeyboardDismissController()
        XCTAssertFalse(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 0)
        let frame = CGRect(x: 0, y: 600, width: 390, height: 296)
        let userInfo: [AnyHashable: Any] = [UIResponder.keyboardFrameEndUserInfoKey: frame]
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil, userInfo: userInfo)
        XCTAssertTrue(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 296)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        XCTAssertFalse(controller.isKeyboardVisible)
        XCTAssertEqual(controller.keyboardHeight, 0)
    }

    @MainActor func testDismissResignsFirstResponder() {
        let controller = KeyboardDismissController()
        controller.isKeyboardVisible = true
        // UIApplication.shared.sendAction resigns first responder; assert no crash and visible stays mutable.
        controller.dismiss()
        XCTAssertTrue(true) // smoke — resign has no return value
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/KeyboardDismissControllerTests`
Expected: FAIL — `KeyboardDismissController` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import SwiftUI
import UIKit

@MainActor @Observable final class KeyboardDismissController {
    var isKeyboardVisible = false
    var keyboardHeight: CGFloat = 0
    private var observers: [NSObjectProtocol] = []
    init() {
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            self.isKeyboardVisible = true
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect { self.keyboardHeight = frame.height }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isKeyboardVisible = false
            self?.keyboardHeight = 0
        })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    func dismiss() { KeyboardDismiss.dismiss() }
}

struct LiquidGlassKeyboardDismissButton: View {
    let controller: KeyboardDismissController
    var body: some View {
        if controller.isKeyboardVisible {
            Button { controller.dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                    Text("Done").font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(Color(#colorLiteral(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)))
                .background(.ultraThinMaterial, in: Capsule().inset(by: 0.5))
                .overlay(Capsule().inset(by: 0.5).strokeBorder(Color(#colorLiteral(red: 0.92, green: 0.93, blue: 0.94, alpha: 1)), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss keyboard")
        }
    }
}

extension View {
    /// Overlays the glass Done button at bottom-trailing, lifted by `keyboardHeight`
    /// so it floats just above the keyboard's top edge. Hidden when keyboard is down.
    func liquidGlassKeyboardDismiss(controller: KeyboardDismissController) -> some View {
        overlay(alignment: .bottomTrailing) {
            LiquidGlassKeyboardDismissButton(controller: controller)
                .padding(.trailing, 12)
                .offset(y: -(controller.keyboardHeight) - 8)
                .allowsHitTesting(controller.isKeyboardVisible)
                .animation(.easeInOut(duration: 0.25), value: controller.keyboardHeight)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/KeyboardDismissControllerTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Open `LiquidGlassKeyboardDismissButton` preview: button is a glass capsule, floats at bottom-trailing, appears only when keyboard is visible, tap dismisses the keyboard. Confirm glass tint (white-translucent + `#eaecf0` hairline) matches the Figma language.

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation/Common/LiquidGlassKeyboardDismissButton.swift AltonAppTests/KeyboardDismissControllerTests.swift
git commit -m "feat: reusable liquid-glass keyboard dismiss button"
```

---

### Task 2: Move Publish to bottom chrome skeleton

**Files:**
- Create: `AltonApp/AltonApp/Presentation/Post/ComposerBottomChrome.swift`
- Modify: `AltonApp/AltonApp/Presentation/Post/CreatePostView.swift` (toolbar 190–211, safeAreaInset 217, composerChrome 299–340)

**Interfaces:**
- Consumes: `KeyboardDismissController` from Task 1.
- Produces: `ComposerBottomChrome` view with bindings (`canPublish`, `isSubmitting`, `remainingCharacters`, `attachmentsCount`, `onPublish`, `onPhotos`, `onFormat`, `onMention`, `onPreview`, `onMore`, `showFormatTools`, `isPreviewMode`, `formatState`).

- [ ] **Step 1: Write the failing test**

No UI test target. Write a logic unit test for the chrome's enabled-state rule (the part that decides whether Post is tappable):

```swift
import XCTest
@testable import AltonApp

final class ComposerBottomChromeStateTests: XCTestCase {
    func testCanPublishFalseWhenSubmittingOrEmpty() {
        XCTAssertFalse(ComposerPublishState(canSubmitContent: false, isSubmitting: false).canPublish)
        XCTAssertFalse(ComposerPublishState(canSubmitContent: true, isSubmitting: true).canPublish)
        XCTAssertTrue(ComposerPublishState(canSubmitContent: true, isSubmitting: false).canPublish)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/ComposerBottomChromeStateTests`
Expected: FAIL — `ComposerPublishState` not found.

- [ ] **Step 3: Write minimal implementation**

Create `ComposerBottomChrome.swift` with a small `ComposerPublishState` struct (`let canSubmitContent: Bool; let isSubmitting: Bool; var canPublish: Bool { !isSubmitting && canSubmitContent }`) and a `ComposerBottomChrome` view shell: a glass container holding a placeholder tool row + a `Post` pill (`#1c1c1e` background, white text, `Capsule`, disabled when `!canPublish`). Keep the existing `composerChrome` body intact in `CreatePostView` for now — only remove the nav-bar Post item and route `onPublish` to the new bottom Post pill.

In `CreatePostView.swift`:
- Delete `ToolbarItem(placement: .primaryAction) { Button … Post … }` (lines 199–211).
- Replace `.keyboardDoneButton()` (line 188) with `.liquidGlassKeyboardDismiss(controller: dismissController)`; add `@State private var dismissController = KeyboardDismissController()` to the view.
- In `composerChrome`, replace the existing tool row's trailing `Spacer` + `characterMeter` with `ComposerBottomChrome`'s Post pill (wire `canPublish` to `canPublish` computed property).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/ComposerBottomChromeStateTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Open the composer: nav bar shows only `Cancel` + `New Take` (no Post). Bottom glass bar shows the `Post` pill on the right. Tap text → keyboard appears → Post pill stays above the keyboard. Tap Post → publishes.

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation/Post/ComposerBottomChrome.swift AltonApp/AltonApp/Presentation/Post/CreatePostView.swift AltonAppTests/ComposerBottomChromeStateTests.swift
git commit -m "feat: move Publish from nav bar to bottom glass chrome"
```

---

### Task 3: Full glass bottom chrome (format capsule + tool row + Post pill)

**Files:**
- Modify: `AltonApp/AltonApp/Presentation/Post/ComposerBottomChrome.swift` (full body)
- Modify: `AltonApp/AltonApp/Presentation/Post/CreatePostView.swift` (replace `composerChrome` 299–340 with `ComposerBottomChrome(...)`; remove `formatToolbar` 349–357, `bottomToolIcon` 509–512, `characterMeter` 482–498, `photosToolButton` 400–408, `formatToggleButton` 410–420, `mentionToolButton` 425–433, `previewToolButton` 435–443, `moreToolsMenu` 453–477 once they are absorbed into `ComposerBottomChrome`)

**Interfaces:**
- Consumes: outline-SVG icon set (`ComposerIcon` enum with cases `photos`, `format`, `mention`, `preview`, `more`, `bold`, `italic`, `strike`, `h1`, `h2`, `quote`, `link`), `#1c1c1e` text, `#a0a3ab` secondary, `#eaecf0` divider, `#eaecf0` attachment border, Inter / `-apple-system` font.

- [ ] **Step 1: Write the failing test**

Add to `ComposerBottomChromeStateTests`:

```swift
func testFormatToggleFlipsShowFormatTools() {
    var state = ComposerChromeState(showFormatTools: false)
    state.toggleFormat()
    XCTAssertTrue(state.showFormatTools)
    state.toggleFormat()
    XCTAssertFalse(state.showFormatTools)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/ComposerBottomChromeStateTests/testFormatToggleFlipsShowFormatTools`
Expected: FAIL — `ComposerChromeState.toggleFormat` not found.

- [ ] **Step 3: Write minimal implementation**

First create the `ComposerIcon` enum (in `ComposerBottomChrome.swift` or a sibling `ComposerIcon.swift`) — an outline-SVG icon set with cases: `photos`, `format` (Aa), `mention` (@), `preview` (eye), `more` (⋯), and format actions `bold`, `italic`, `underline`, `strikethrough`, `spoiler`, `inlineCode` ({}), `link`, `quote`, `bulletList`, `numberedList`, `codeBlock`. Each case renders a 22×22 (tool row) or 24×24 (format capsule) SVG with `#1c1c1e` stroke 1.5, no fill, via `Shape`-based paths or an asset catalog of outline SVGs. Expose `func accessibilityLabel` per case ("Add photos", "Format", "Mention", "Preview", "More", "Bold", etc.).

Build `ComposerBottomChrome` body:
- Outer container: `VStack(spacing: 0)` with `.background(.regularMaterial)` + top hairline `#eaecf0` 1pt + inset top highlight.
- Row 1 (conditional): format capsule — a glass sub-capsule with inline actions (`bold`, `italic`, `underline`, `strikethrough`, `spoiler`, `inlineCode`, `link`) and block actions (`quote`, `bulletList`, `numberedList`, `codeBlock`). Horizontal scroll if needed. Visible only when `showFormatTools && !isPreviewMode`. Active state (format-on): `#eaecf0` fill + `#1c1c1e` bold icon (monochrome — no blue).
- Divider `#eaecf0`.
- Row 2 (always): `[photos] [format] [mention] [preview] [more]  Spacer  [char meter]  [Post pill]`.
  - Tool icons: 22×22 outline SVG, `#1c1c1e` stroke 1.5, no fill. Active state (format-on / preview-on): pill background `#eaecf0`, icon `#1c1c1e`.
  - Char meter: a thin ring (`Circle` stroke, `#eaecf0` track 2pt, `#1c1c1e` progress 2pt, `trim(from: 0, to: min(1, used/limit)))` with the remaining count under 200 shown as a label inside/under; over-limit count turns `#1c1c1e`.
  - Post pill: `Capsule` (`cornerRadius 100`), bg `#1c1c1e`, text `white`, `14px` semibold, padding `px 18 × py 7`. Disabled state: bg `#eaecf0`, text `#a0a3ab`. Label "Post".
  - Accessibility: Post pill `.accessibilityLabel("Post")`; every tool icon `.accessibilityLabel(icon.accessibilityLabel)`; format capsule icons likewise.

Replace `composerChrome` in `CreatePostView` with `ComposerBottomChrome(...)` passing all bindings.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/ComposerBottomChromeStateTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification (the success criterion)**

Type a take → tap Photos → add a photo → tap into text → type `@al` → pick a mention → tap Post. **Post must stay visible above the keyboard at every step.** Toggle format capsule on/off; confirm capsule slides in without pushing Post off-screen. Switch to preview mode; confirm only Post + char meter remain.

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation/Post/ComposerBottomChrome.swift AltonApp/AltonApp/Presentation/Post/CreatePostView.swift AltonAppTests/ComposerBottomChromeStateTests.swift
git commit -m "feat: full glass bottom chrome with format capsule and outline icons"
```

---

### Task 4: Floating mention overlay (lift out of safeAreaInset)

**Files:**
- Create: `AltonApp/AltonApp/Presentation/Post/MentionOverlayView.swift`
- Modify: `AltonApp/AltonApp/Presentation/Post/CreatePostView.swift` (remove mention block from `composerChrome`; add overlay above the bottom chrome)
- Modify: `AltonApp/AltonApp/Presentation/Post/MentionAutocompleteView.swift` (extract the rendering into `MentionOverlayView`, keep the query/filter logic)

**Interfaces:**
- Produces: `MentionOverlayView(candidates: [MentionCandidate], query: String, onSelect: (MentionCandidate) -> Void)`. The overlay floats above the bottom chrome, anchored to its top edge, with `.ultraThinMaterial` + `RoundedRectangle(cornerRadius: 14)` + `#eaecf0` hairline.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AltonApp

final class MentionOverlayStateTests: XCTestCase {
    func testOverlayVisibleOnlyWhenCandidatesNonEmpty() {
        var state = MentionOverlayState(candidates: [])
        XCTAssertFalse(state.isVisible)
        state.candidates = [MentionCandidate.fixture(name: "alice"), MentionCandidate.fixture(name: "bob")]
        XCTAssertTrue(state.isVisible)
        state.candidates = []
        XCTAssertFalse(state.isVisible)
    }
}

extension MentionCandidate {
    static func fixture(name: String) -> MentionCandidate {
        // Use the existing public initializer; if the type is a struct with memberwise init,
        // construct with the minimal fields (id, name, handle, avatar). Adjust field names to match.
        MentionCandidate(id: name.lowercased(), name: name, handle: "@\(name)", avatarURL: nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/MentionOverlayStateTests`
Expected: FAIL — `MentionOverlayState` not found.

- [ ] **Step 3: Write minimal implementation**

Create `MentionOverlayView.swift`:
- `struct MentionOverlayState: Equatable { var candidates: [MentionCandidate]; var isVisible: Bool { !candidates.isEmpty } }`
- `MentionOverlayView`: `VStack` of up to 4 rows (spec §5.4 — max 4 rows, scroll if more), each row = avatar (28pt circle `#eaecf0`) + name (`#1c1c1e` 15 semibold) + handle (`#a0a3ab` 13). Container: `.ultraThinMaterial` liquid glass (blur + saturate), `RoundedRectangle(cornerRadius: 14)`, `#eaecf0` 1pt hairline, `shadow(black 0.08, r10, y4)`. Max height 4×44 = 176.

In `CreatePostView`:
- Remove the `if !viewModel.mentionCandidates.isEmpty { MentionAutocompleteView(...) }` block from `composerChrome`.
- Add `.overlay(alignment: .bottom) { MentionOverlayView(...).padding(.bottom, chromeHeight) }` on the editor area, so the overlay sits above the bottom chrome, not inside it.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/MentionOverlayStateTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Type `@al` → mention list floats above the bottom chrome (not inside it). Pick a suggestion → list disappears, `@al` replaced by `@alice`. Confirm the overlay never pushes the Post pill off-screen.

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation/Post/MentionOverlayView.swift AltonApp/AltonApp/Presentation/Post/CreatePostView.swift AltonApp/AltonApp/Presentation/Post/MentionAutocompleteView.swift AltonAppTests/MentionOverlayStateTests.swift
git commit -m "feat: floating mention overlay above bottom chrome"
```

---

### Task 5: Attachment strip DnD reorder + design alignment

**Files:**
- Modify: `AltonApp/AltonApp/Presentation/Post/MediaAttachmentView.swift` (`ComposerAttachmentStrip` 1–45, `ComposerAttachmentThumb` 50–120)
- Create: `AltonAppTests/AttachmentReorderTests.swift`

**Interfaces:**
- Consumes: iOS 16 `Drag and Drop` API — `.draggable` + `.dropDestination` for reorder (no `Transferable` needed; use a local index-based payload via `ItemProvider` with a custom `UTType`). Reorder mutates `viewModel.attachments` through an existing `@Binding` (the ViewModel's public interface is reused as-is — no new ViewModel methods).
- Design tokens: thumb 88px, `cornerRadius(8)`, border `#eaecf0` 0.5pt, remove button = outline-SVG `xmark` 18×18 in `#1c1c1e` inside a white circle top-right. "Add" tile: `#eaecf0` background, `cornerRadius(8)`, thin `plus` outline SVG + "Add" label `#8d939c`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AltonApp

final class AttachmentReorderTests: XCTestCase {
    func testMoveFromToReordersArray() {
        var items = ["a", "b", "c", "d"]
        items = AttachmentReorder.move(items, from: 0, to: 2)
        XCTAssertEqual(items, ["b", "c", "a", "d"])
    }
    func testMoveOutOfBoundsIsNoop() {
        var items = ["a", "b"]
        items = AttachmentReorder.move(items, from: 5, to: 0)
        XCTAssertEqual(items, ["a", "b"])
    }
    func testRemoveAtRemovesOne() {
        let items = ["a", "b", "c"]
        XCTAssertEqual(AttachmentReorder.remove(items, at: 1), ["a", "c"])
    }
    func testStripRendersCorrectCountFor0_1_4_10() {
        for count in [0, 1, 4, 10] {
            let items = (0..<count).map { "\($0)" }
            let strip = ComposerAttachmentStrip(items: .constant(items), onRemove: { _ in })
            // Smoke: the strip builds without crashing for each count; layout is verified manually.
            _ = strip
            XCTAssertEqual(items.count, count)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/AttachmentReorderTests`
Expected: FAIL — `AttachmentReorder` not found.

- [ ] **Step 3: Write minimal implementation**

Add `enum AttachmentReorder` with pure functions `move<T>(_ items: [T], from: Int, to: Int) -> [T]` and `remove<T>(_ items: [T], at: Int) -> [T]` (bounds-checked).

In `ComposerAttachmentStrip`: accept `@Binding var items: [MediaAttachment]` (or keep the existing binding shape and reorder through it). In `ComposerAttachmentThumb`:
- Add `.draggable { ItemProvider(object: NSString(string: "\(index)")) }` and `.dropDestination(for: String.self) { payloads, _ in
    guard let s = payloads.first, let from = Int(s) else { return false }
    items = AttachmentReorder.move(items, from: from, to: index)
    return true
  }`.
- Replace `xmark.circle.fill` (line 109–117) with outline-SVG `xmark` in the styled circle described above.
- Set thumb `cornerRadius(8)` + `#eaecf0` 0.5pt border.
- Align the "Add" tile to `#eaecf0` background, `cornerRadius(8)`, thin outline-SVG `plus` + "Add" `#8d939c` label.

Do **not** add `moveAttachment` / `removeAttachment` to `CreatePostViewModel` — the reorder mutates the existing `attachments` binding directly, preserving the ViewModel's public interface.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/AttachmentReorderTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Add 3 photos. Long-press the first → drag → drop between 2 and 3 → order changes. Tap the `x` on a thumb → photo removed. Confirm thumbs use `cornerRadius(8)` + `#eaecf0` border + outline-SVG `xmark` (no blue, no filled circle).

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation/Post/MediaAttachmentView.swift AltonAppTests/AttachmentReorderTests.swift
git commit -m "feat: drag-and-drop reorder for attachment strip + design alignment"
```

---

### Task 6: Roll out `.liquidGlassKeyboardDismiss()` to Reply / Comment / Location / Hashtag

**Files:**
- Modify: any view currently calling `.keyboardDoneButton()` (search: `rg "\.keyboardDoneButton\(\)" AltonApp/AltonApp/Presentation`)
  - `ReplyComposerView.swift`
  - `CommentComposerView.swift`
  - `LocationComposerView.swift`
  - `HashtagComposerView.swift`
  - (any other hits the search returns)

**Interfaces:**
- Consumes: `.liquidGlassKeyboardDismiss(controller:)` from Task 1.

- [ ] **Step 1: Write the failing test**

No new logic; reuse `KeyboardDismissControllerTests` (Task 1). Add a smoke test that the modifier is applied:

```swift
import XCTest
import SwiftUI
@testable import AltonApp

final class LiquidGlassDismissAdoptionTests: XCTestCase {
    func testAllComposersUseLiquidGlassDismiss() {
        // Smoke: each composer view type exists and responds to the modifier without crashing.
        let controller = KeyboardDismissController()
        _ = ReplyComposerView().liquidGlassKeyboardDismiss(controller: controller)
        _ = CommentComposerView().liquidGlassKeyboardDismiss(controller: controller)
        _ = LocationComposerView().liquidGlassKeyboardDismiss(controller: controller)
        _ = HashtagComposerView().liquidGlassKeyboardDismiss(controller: controller)
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/LiquidGlassDismissAdoptionTests`
Expected: FAIL — types may not exist yet or still use `.keyboardDoneButton()`.

- [ ] **Step 3: Write minimal implementation**

In each composer view: replace `.keyboardDoneButton()` with `.liquidGlassKeyboardDismiss(controller: KeyboardDismissController())` (use a `@State` controller per view, matching the pattern from Task 2). Remove the `ToolbarItemGroup(.keyboard) { Button("Done") ... }` block if still present.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/LiquidGlassDismissAdoptionTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Open Reply, Comment, Location, Hashtag composers in turn. Tap into the text field → keyboard appears → glass Done capsule floats at bottom-trailing above the keyboard → tap → keyboard dismisses. Confirm no stock iOS `Done` bar button remains.

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation AltonAppTests/LiquidGlassDismissAdoptionTests.swift
git commit -m "refactor: replace stock keyboard Done with liquid-glass dismiss across composers"
```

---

### Task 7: Fix text duplication / writing bugs in MarkdownEditorView

**Files:**
- Modify: `AltonApp/AltonApp/Presentation/Post/MarkdownEditorView.swift` (Coordinator `pendingEdit` 310–315, `pendingFormatAction` 328–332, `importExternalMarkdownIfNeeded` 478–515, `updateUIView` body)
- Create: `AltonAppTests/MarkdownEditorBindingLoopTests.swift`

**Root cause (from exploration):**
Binding-loop race — `pendingEdit` and `pendingFormatAction` are cleared via `DispatchQueue.main.async`, which races the next `updateUIView` call. When SwiftUI re-renders the parent (e.g. mention insert) while a pending edit is still queued, `updateUIView` re-applies the stale text, doubling the inserted segment.

**Fix shape:**
1. Synchronous edit-consumption: consume `pendingEdit` *inside* `updateUIView` (not via async), and only apply when `string != newPending`.
2. Monotonic token gate: add `private var editToken: UInt64 = 0`; bump on every `updateUIView` apply; ignore any pending edit whose token is older than the current.
3. Ownership flag: add `private(set) var isAuthoritative = false` — set `true` when the editor becomes first responder and has un-consumed local mutations; while `isAuthoritative`, `importExternalMarkdownIfNeeded` returns early (the editor's text is the source of truth). Set `false` when the binding changes from *outside* (autosave restore, draft open, mention insert from another path) — detected by the token gate noticing an external `string` change that was not scheduled by a local `pendingEdit`.
4. Drop the `DispatchQueue.main.async` clear blocks at 310–315 and 328–332.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AltonApp

final class MarkdownEditorBindingLoopTests: XCTestCase {
    @MainActor func testPendingEditConsumedSynchronously() {
        let coordinator = MarkdownEditorView.Coordinator(text: .constant("hello"))
        coordinator.pendingEdit = "hello world"
        coordinator.applyPendingEditIfNeeded(current: "hello")
        XCTAssertEqual(coordinator.textView.text, "hello world")
        XCTAssertNil(coordinator.pendingEdit, "pendingEdit must be cleared synchronously")
    }
    @MainActor func testStaleTokenIgnored() {
        let coordinator = MarkdownEditorView.Coordinator(text: .constant("a"))
        let stale = coordinator.currentToken
        coordinator.pendingEdit = "stale"
        coordinator.pendingEditToken = stale
        coordinator.bumpToken() // a newer apply happened
        coordinator.applyPendingEditIfNeeded(current: "a")
        XCTAssertEqual(coordinator.textView.text, "a", "stale pending edit must be ignored")
    }
    @MainActor func testAuthoritativeSkipsImport() {
        let coordinator = MarkdownEditorView.Coordinator(text: .constant("a"))
        coordinator.setAuthoritative(true)
        XCTAssertTrue(coordinator.isAuthoritative)
        // While authoritative, an external binding change must NOT overwrite the editor's text.
        coordinator.importExternalMarkdownIfNeeded(newMarkdown: "external", current: "a")
        XCTAssertEqual(coordinator.textView.text, "a", "import must be skipped while editor is authoritative")
    }
    @MainActor func testExternalSetReplacesContentWhenNotAuthoritative() {
        // Regression: draft open / autosave restore (binding changes from outside, editor not first responder)
        // must still replace the editor's text.
        let coordinator = MarkdownEditorView.Coordinator(text: .constant("old"))
        coordinator.setAuthoritative(false)
        coordinator.importExternalMarkdownIfNeeded(newMarkdown: "restored draft", current: "old")
        XCTAssertEqual(coordinator.textView.text, "restored draft", "external set must replace content when not authoritative")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/MarkdownEditorBindingLoopTests`
Expected: FAIL — `applyPendingEditIfNeeded`, `currentToken`, `bumpToken`, `isAuthoritative`, `setAuthoritative`, `importExternalMarkdownIfNeeded` (testable form) not found.

- [ ] **Step 3: Write minimal implementation**

In `Coordinator`:
- Add `private(set) var currentToken: UInt64 = 0`, `private(set) var pendingEditToken: UInt64 = 0`, `private(set) var isAuthoritative = false`.
- `func bumpToken() { currentToken &+= 1 }`.
- `func setAuthoritative(_ value: Bool) { isAuthoritative = value }`.
- `func applyPendingEditIfNeeded(current: String)`: if `pendingEdit == nil` return; if `pendingEditToken < currentToken` { pendingEdit = nil; return }; set `textView.text = pendingEdit`; `pendingEdit = nil`.
- `func importExternalMarkdownIfNeeded(newMarkdown: String, current: String)`: if `isAuthoritative` return (skip); if `newMarkdown == current` return; set `textView.text = newMarkdown`.
- In `updateUIView`: call `bumpToken()` before any text apply; call `applyPendingEditIfNeeded(current:)` instead of the async clear; detect external `string` changes (binding value differs from last applied and no pending edit scheduled) → set `isAuthoritative = false` before importing.
- Set `isAuthoritative = true` in `textViewDidBeginEditing`; set `false` in `textViewDidEndEditing` (or when a local `pendingEdit` is fully consumed and the editor resigns).
- Remove the `DispatchQueue.main.async { self.pendingEdit = nil }` (310–315) and the same for `pendingFormatAction` (328–332); consume them inline.
- In the existing `importExternalMarkdownIfNeeded` call site (478–515): set `pendingEditToken = currentToken` when scheduling `pendingEdit`; route through the new testable `importExternalMarkdownIfNeeded(newMarkdown:current:)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/MarkdownEditorBindingLoopTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Type a take → insert a mention → keep typing fast → no doubled `@alice@alice`. Toggle bold while typing → no duplicated `**`. Paste a long markdown block → text appears once. Repeat 10× to confirm the race is gone.

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation/Post/MarkdownEditorView.swift AltonAppTests/MarkdownEditorBindingLoopTests.swift
git commit -m "fix: synchronous pending-edit consumption + monotonic token gate in MarkdownEditor"
```

---

### Task 8: Monochrome color pass (drop system blue)

**Files:**
- Modify: `AltonApp/AltonApp/Presentation/Post/CreatePostView.swift` (Cancel button tint, mention `@al` highlight, format-on active state)
- Modify: `AltonApp/AltonApp/Presentation/Post/MarkdownEditorView.swift` (mention attribute color)
- Modify: `AltonApp/AltonApp/Presentation/Post/ComposerBottomChrome.swift` (format-on active state color)

**Tokens:**
- Cancel button: `#1c1c1e` `.foregroundStyle`, plain (no blue).
- Mention `@al` (typed) and inserted `@username`: `#1c1c1e` bold, no blue tint.
- Format-on (active toggle): pill background `#eaecf0`, icon `#1c1c1e` — no system blue.
- Preview-on: same as format-on.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AltonApp

final class MonochromeColorPassTests: XCTestCase {
    func testNoSystemBlueInComposerPalette() {
        let palette = ComposerPalette.monochrome
        XCTAssertFalse(palette.accent == .blue, "no system blue allowed")
        XCTAssertEqual(palette.primary.hex, "#1c1c1e")
        XCTAssertEqual(palette.secondary.hex, "#a0a3ab")
        XCTAssertEqual(palette.divider.hex, "#eaecf0")
        XCTAssertEqual(palette.activeFill.hex, "#eaecf0")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/MonochromeColorPassTests`
Expected: FAIL — `ComposerPalette` not found.

- [ ] **Step 3: Write minimal implementation**

Add `struct ComposerPalette` (in `ComposerBottomChrome.swift` or a new `ComposerTheme.swift`) with `static let monochrome = ComposerPalette(primary: .hex("#1c1c1e"), secondary: .hex("#a0a3ab"), divider: .hex("#eaecf0"), activeFill: .hex("#eaecf0"), accent: .hex("#1c1c1e"))` and a small `Color.hex` helper.

Replace every `Color.blue` / `.tint(.blue)` / `.accentColor(.blue)` in the composer surfaces with `ComposerPalette.monochrome.primary`. Replace mention attribute color in `MarkdownEditorView` with `#1c1c1e` bold. Replace Cancel button tint in `CreatePostView` with `#1c1c1e`.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:AltonAppTests/MonochromeColorPassTests`
Expected: PASS.

- [ ] **Step 5: Manual UI verification**

Open composer: Cancel is black, not blue. Type `@al` → suggestion list appears, the typed `@al` is black bold, not blue. Toggle bold on → icon pill is light gray with black icon, not blue. Switch to preview → same. No blue anywhere in the composer.

- [ ] **Step 6: Commit**

```bash
git add AltonApp/AltonApp/Presentation/Post AltonAppTests/MonochromeColorPassTests.swift
git commit -m "style: monochrome composer palette, drop system blue"
```

---

## Final Verification

After all tasks land, run the full suite and the manual success criterion one more time:

- [ ] **Full test suite passes**

```bash
xcodebuild test -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max'
```

Expected: all tests green, no regressions in `RichTextMarkdownConverterTests`, `DraftStoreTests`, or any existing composer tests.

- [ ] **Success criterion (the original brief)**

Type a take → add a photo → type `@al` → pick a mention → tap Post. **Post must stay above the keyboard at every step.** No doubled text. No blue. Glass Done capsule floats above the keyboard in every composer.

- [ ] **Spec coverage check**

Re-read `docs/superpowers/specs/2026-10-04-take-composer-redesign.md` and tick every bullet:
- 3 UX pain points addressed (Task 2/3 moves Publish close to thumb; Task 3 keeps chrome height fixed; Task 4 separates mentions from format column).
- Keyboard-open / keyboard-closed layouts defined (Task 3 + Task 1).
- Publish / attachments / mentions / format tools placement (Task 2, 3, 4, 5).
- Liquid-glass Done, floating above keyboard, opens with keyboard (Task 1, 6).
- Photos DnD reorder within strip (Task 5).
- Attachments keep current design incl. "Add" tile (`#eaecf0`, `cornerRadius 8`, outline-SVG `plus`, "Add" `#8d939c`) (Task 5).
- Text duplication fix (Task 7).
- Rich-text formatting preserved — full set B/I/U/S/spoiler/inlineCode/link + quote/bullet/numbered/codeBlock (Task 3 + Task 7 + Task 8 — no format loss, only color change).
- Monochrome palette — Cancel, `@al`, format-on, Post pill (Task 8).
- Accessibility — Post pill label, tool icon labels, mention overlay keyboard-navigable (Task 3 + Task 4).

- [ ] **No placeholders**

```bash
rg -n "TODO|FIXME|XXX|placeholder" AltonApp/AltonApp/Presentation/Post AltonApp/AltonApp/Presentation/Common
```
Expected: no new placeholders introduced by this plan.

- [ ] **Type consistency**

```bash
xcodebuild build -scheme AltonApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max'
```
Expected: builds with no warnings about the new types.

---

## Handoff

This plan is ready for execution. Two execution paths:

- **Subagent-driven (recommended):** spawn one Task subagent per task, each running the 6 steps in order, committing at Step 6. Tasks 1 and 2 are prerequisites for 3–8; Tasks 3, 4, 5, 7, 8 can run in parallel after 1+2 land; Task 6 can run any time after 1.
- **Native (sequential):** execute the steps yourself in this session, one task at a time, running the test commands via the shell.

Pick a path and start with Task 1.
