# Take Composer Redesign — Design Spec

**Date:** 2026-10-04
**Status:** Approved (visual mockup v6), pending written-spec review
**Screen:** `CreatePostView` (New Take / Edit Take)
**Path:** `AltonApp/AltonApp/Presentation/Post/CreatePostView.swift`

## 1. Overview

Redesign the Take composer so the primary flow — type a take + add a photo + insert a mention + publish — happens in one thumb zone, without losing the Publish button under the keyboard, and in the visual language of the Alton app (Figma: `Trade — Alton`, node `11432:34044`): light `#ffffff` background, `#1c1c1e` text, Apple system font, `#eaecf0` dividers, monochrome thin-outline iconography, and iOS 26 liquid-glass on floating elements.

## 2. Goals & Success Criteria

- Type a take + attach a photo + insert a mention + publish without the Publish button ever being hidden under the keyboard and without reaching to the top-right corner.
- Publish lives in the bottom chrome, in the thumb zone, above the keyboard.
- Mentions and format tools stop competing for one stacked column; mentions float, format tools are a contextual capsule.
- A reusable liquid-glass keyboard-dismiss button that always appears with the keyboard and floats over it.
- Attachments support drag-and-drop reorder within the strip, keeping the current attachment design.
- Fix the text-duplication / writing-error bugs in the markdown editor binding loop.
- Preserve all rich-text formatting (bold, italic, underline, strikethrough, spoiler, inline code, link, quote, bullet list, numbered list, code block).

## 3. Non-Goals (do not touch)

- Shot cover selection
- Camera capture (`CameraView`)
- Video editor / timeline / composition / export
- Comments (`CommentsView`, `ShotCommentsSheet`)
- ViewModel / API (`CreatePostViewModel`, `PostUseCase`) — only the view layer changes; the ViewModel's public interface is reused as-is
- The feed post card (`TakePostView`) — this spec is the composer only

## 4. Current Pain Points

1. **Publish in the wrong zone.** `ToolbarItem(placement: .primaryAction)` renders Post in the top-right nav bar (`CreatePostView.swift:199`). All tools (photo, mention, format, char meter) sit in the bottom `composerChrome` via `safeAreaInset(.bottom)` (`:299`, `:329`). Type → reach down for photo → reach down for mention → reach **up** to publish. Long thumb travel on a tall phone with the keyboard up.
2. **Bottom chrome grows vertically and squeezes the editor.** `chromeHeight` sums 57 + 46 (format) + up to ~216 (mentions, 4 rows × 52 + 8) (`:78`, `:84`). Mentions + format + tool bar + keyboard stack tall; the mention list is crammed into the same column instead of floating.
3. **Format tools hidden and competing.** `showFormatTools` opens only on text selection (`:117`) or a toggle (`:410`); no persistent affordance. Format toolbar sits between the mention list and the tool bar (`:318`). Record-shot and remove-all-photos buried in `moreToolsMenu` (`:453`). Grouping (persistent vs contextual vs menu) is unreadable.
4. **Keyboard dismiss is stock.** `Button("Done")` in `ToolbarItemGroup(placement: .keyboard)` (`KeyboardDismiss.swift:38`) — plain text in the system keyboard toolbar, not liquid glass, not floating, not always visually paired with the keyboard.

## 5. Design — Approach A (approved)

Model: X / Twitter / Threads compose. Publish in the bottom chrome, right side. Single thumb zone.

### 5.1 Navigation bar
- Left: `Cancel` — `#1c1c1e` text button (matches the app's monochrome language; drops the current system-blue text).
- Center: `New Take` / `Edit Take` title, `#1c1c1e`, semibold.
- Right: empty (Publish moved to bottom). Optional: a small "Draft saved" indicator.

### 5.2 Editor area (unchanged structure)
- Avatar 40px (gradient circle) + `username` (`#1c1c1e`, 15px, semibold) + `MarkdownEditorView`.
- Editor text `#1c1c1e`, 15–16px, Apple system font, leading 1.4. Placeholder `#a0a3ab`.
- Mention token `@al` rendered `#1c1c1e` **bold** (monochrome — no system blue; preserves affordance via weight, not color).

### 5.3 Attachment strip (current design + DnD)
- Keeps `ComposerAttachmentStrip` / `ComposerAttachmentThumb` visual: 88px thumbs, `cornerRadius 8` (aligned to Figma media boxes), `0.5px #eaecf0` border.
- Remove control: `xmark` in a white circle, top-right (outline SVG style, not the current `xmark.circle.fill` palette emoji).
- "Add" tile: `#eaecf0` background, `cornerRadius 8`, thin `plus` outline SVG + "Add" `#8d939c` label.
- **DnD reorder (new):** long-press a thumb lifts it (haptic), drag to reorder within the strip; drop snaps with animation. Only reorder within the strip (no cross-app drag in/out). A subtle grip hint appears on long-press. Reorder reorders `viewModel.attachments` and updates `loadedPickerItemIDs`.

### 5.4 Mention overlay (floating, not inset)
- `MentionAutocompleteView` rendered as a **floating glass capsule** that sits **above** the bottom chrome, anchored near the caret — not inside `safeAreaInset(.bottom)`.
- It no longer contributes to `chromeHeight`; the editor is never squeezed by it.
- Glass: white-translucent liquid glass, `cornerRadius 14`, `#eaecf0` hairline, blur + saturate. Max 4 rows, scroll if more.
- Selection inserts `@username ` via the existing `pendingEdit` / `MentionPickerModel.activeRange` path.

### 5.5 Bottom chrome (liquid glass)
- Single glass container (white-translucent, blur + saturate, `#eaecf0` top hairline, inset top highlight) hosting two rows:
  - **Format capsule (contextual):** a glass sub-capsule with inline actions (B, I, U, S, spoiler, { }, link) and block actions (quote, bullet list, numbered list, code block). Opens on text selection or the `Aa` toggle. Active state: `#eaecf0` fill + `#1c1c1e` bold (monochrome — no blue).
  - **Tool row (persistent):** photos picker (add photos — the `photo.on.rectangle.angled` slot, outline SVG), `Aa` (format toggle), `@` (mention), eye (preview), `⋯` (more: record shot, remove all photos). All thin-outline SVG, `#1c1c1e`, 22px. The "Record shot" (actual camera) stays in the `⋯` more menu, as today.
  - Right side: character meter (thin ring, `#eaecf0` track, `#1c1c1e` progress, shows count under 200 left) + **Post** pill.
- **Post pill:** `#1c1c1e` background, white text, `cornerRadius 100` (full pill), 14px semibold, `px 18 × py 7`. Disabled state: `#eaecf0` background, `#a0a3ab` text. Matches the app's composer CTA language (`CommentComposerFullScreenView` Reply capsule uses `Color.primary` + `Color(.systemBackground)`).

### 5.6 Liquid-glass keyboard-dismiss button (reusable, new)
- A standalone reusable component (e.g. `LiquidGlassKeyboardDismissButton`) replacing the `keyboardDoneButton()` modifier.
- Floats **over** the keyboard's top edge, right side, always visible while the keyboard is up; appears/disappears with the keyboard (driven by keyboard visibility, not a static toolbar item).
- Glass: white-translucent liquid glass (blur + saturate + inset highlight + `#eaecf0`-ish hairline), `cornerRadius 100` (pill), `#1c1c1e` chevron-down + "Done" label, 13–14px semibold.
- Action: resign first responder (same as `KeyboardDismiss.dismiss()`).
- Reusable across all composer screens (Take composer, Reply, Comment composer, location picker, hashtag sheet — any screen using `keyboardDoneButton()`).

## 6. Text Duplication / Writing-Error Fix

**Root cause (surface):** the two-way binding loop `viewModel.content` ↔ `RichTextEditorView` via `importExternalMarkdownIfNeeded` (`MarkdownEditorView.swift:478`). Insertion paths (`pendingEdit` → `commit` → `textViewDidChange` → export markdown → `onMarkdownChange` → `updateUIView` → re-import) clear `pendingEdit` / `pendingFormatAction` via async dispatch, racing the next `updateUIView`, which can double-apply an edit or re-import a stale snapshot.

**Approach (view-layer, no ViewModel/API change):**
- Synchronize edit-consumption with the runloop: clear `pendingEdit` / `pendingFormatAction` **synchronously** in the same `updateUIView` pass that applies them (not `DispatchQueue.main.async`), and gate `importExternalMarkdownIfNeeded` on a monotonic edit-generation token so a just-applied edit cannot trigger a re-import.
- Add a single-source-of-truth "import vs export" ownership flag: while the editor is first responder and has un-consumed local mutations, skip `importExternalMarkdownIfNeeded` entirely (the editor is authoritative); only import when the binding changes from outside (autosave restore, draft open, mention insert from another path).
- Reproduce the duplication case (rapid typing + mention insert + format apply) as a UI test before and after the fix.

**Investigation step before implementation:** reproduce the exact trigger (record a screen recording / add a debug log of `importExternalMarkdownIfNeeded` entry/exit) to confirm the root cause, since the guards today are non-trivial. The fix lives in `MarkdownEditorView.swift` / `RichTextEditorView` Coordinator (in scope — "editor" in the non-goals list refers to the **video** editor, not the text editor).

## 7. Components Affected

- `CreatePostView.swift` — main restructure: remove Publish from nav bar; add bottom glass chrome with format capsule + tool row + Post pill; render mention overlay as floating; adopt `LiquidGlassKeyboardDismissButton`.
- `ComposerAttachmentStrip` / `ComposerAttachmentThumb` (`MediaAttachmentView.swift`) — add DnD reorder; align thumb radius / border to `#eaecf0` / `cornerRadius 8`; replace `xmark.circle.fill` with the outline-SVG remove control.
- `MentionAutocompleteView.swift` — keep list UI; lift placement out of `safeAreaInset` into a floating overlay.
- `KeyboardDismiss.swift` — add `LiquidGlassKeyboardDismissButton` (UIViewRepresentable or SwiftUI overlay observing keyboard insets); deprecate `keyboardDoneButton()` modifier or reroute it to the new component.
- `MarkdownEditorView.swift` / `RichTextEditorView` Coordinator — fix the binding-loop race (Section 6).
- No changes to `CreatePostViewModel`, `PostUseCase`, camera, video editor, comments, shot cover.

## 8. Testing

- **Unit/snapshot:** bottom chrome layout (format capsule open/closed, mention overlay shown/hidden, Post enabled/disabled); attachment strip with 0/1/4/10 items; DnD reorder produces the expected `attachments` order.
- **UI test (success criterion):** type a take → add a photo → insert a mention → publish, all with the keyboard up; assert the Post button is visible above the keyboard at the moment of publish; assert no text duplication after rapid typing + mention insert + format apply.
- **Regression:** editor two-way binding (external set: draft open, autosave restore) still replaces content correctly; format actions still apply to the right range.
- **Accessibility:** Post pill is a button with "Post" label; tool icons have accessibility labels; mention overlay is keyboard-navigable.

## 9. Scale Notes

This is a client-only UI change; no backend, sharding, or Kafka impact. The growth story for composer drafts is unchanged (existing `DraftStore` TTL/prune). No new data.

## 10. Open Questions

1. **Cancel color:** drop system blue for `#1c1c1e` (monochrome, matches Figma) or keep the current blue? Mockup v6 uses `#1c1c1e`. → *decision needed*.
2. **Mention color:** `#1c1c1e` bold (monochrome) vs keep `UIColor.link` (blue) for the `@al` token. Mockup v6 uses `#1c1c1e` bold. → *decision needed*.
3. **Dismiss button scope:** replace `keyboardDoneButton()` everywhere (Take, Reply, Comment, Location, Hashtag) in this change, or just the Take composer and roll out incrementally? → *decision needed*.
4. **DnD gesture:** SwiftUI `.draggable`/`.dropDestination` (iOS 16+) vs a custom long-press lift gesture. `.draggable` is lighter; custom gives more control over the lift animation. → *recommend `.draggable`/`.dropDestination` first; custom only if it feels wrong*.
