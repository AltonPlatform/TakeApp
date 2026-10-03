#!/usr/bin/env python3
"""Product rename Thread→Take, Video→Shot in AltonApp Swift sources (excludes technical camera/editor paths)."""
from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "AltonApp"
SKIP_DIR_PARTS = {".derivedData", "SourcePackages"}

# Files under these path segments keep technical "Video*" names (capture/editor).
TECH_PATH_MARKERS = (
    "/Domain/Camera/",
    "/Domain/Editor/",
    "VideoCaptureProcessor.swift",
    "VideoClip.swift",
    "EditorVideoCompositor.swift",
    "VideoQuality.swift",
    "VideoTrackView.swift",
)


def should_process(path: Path) -> bool:
    if path.suffix != ".swift":
        return False
    s = str(path)
    if any(part in s for part in SKIP_DIR_PARTS):
        return False
    return True


def is_technical_file(path: Path) -> bool:
    s = str(path)
    return any(m in s for m in TECH_PATH_MARKERS)


# Order matters: longer / more specific tokens first.
REPLACEMENTS: list[tuple[str, str]] = [
    # Shot feed UI types
    ("VideoFeedPagingViewController", "ShotFeedPagingViewController"),
    ("VideoFeedPagingCell", "ShotFeedPagingCell"),
    ("VideoFeedVerticalPager", "ShotFeedVerticalPager"),
    ("VideoFeedPlaybackCache", "ShotFeedPlaybackCache"),
    ("VideoFeedViewModel", "ShotFeedViewModel"),
    ("VideoFeedPagerView", "ShotFeedPagerView"),
    ("VideoFeedPageView", "ShotFeedPageView"),
    ("VideoFeedSafeAreaModifier", "ShotFeedSafeAreaModifier"),
    ("VideoFeedView", "ShotFeedView"),
    ("VideoCommentsPresentation", "ShotCommentsPresentation"),
    ("VideoCommentsSheet", "ShotCommentsSheet"),
    ("VideoOptionsSheet", "ShotOptionsSheet"),
    ("VideoPlayerView", "ShotPlayerView"),
    ("VideoGestureOverlay", "ShotGestureOverlay"),
    ("VideoProgressBar", "ShotProgressBar"),
    ("VideoPlaybackSpeed", "ShotPlaybackSpeed"),
    ("VideoLikeBurstOverlay", "ShotLikeBurstOverlay"),
    ("VideoLikeBurstItem", "ShotLikeBurstItem"),
    ("VideoLikeBurst", "ShotLikeBurst"),
    ("VideoSpeedZoneOverlay", "ShotSpeedZoneOverlay"),
    ("VideoSpeedZoneView", "ShotSpeedZoneView"),
    ("VideoSpeedZoneUIView", "ShotSpeedZoneUIView"),
    ("VideoSpeedZone", "ShotSpeedZone"),
    ("VideoHaptics", "ShotHaptics"),
    ("VideoPublicationView", "ShotPublicationView"),
    # Takes UI
    ("ThreadsFeedViewModel", "TakesFeedViewModel"),
    ("ThreadsFeedView", "TakesFeedView"),
    ("ThreadPostDetailView", "TakePostDetailView"),
    ("ThreadPostView", "TakePostView"),
    ("ThreadMarkdownContent", "TakeMarkdownContent"),
    ("ReplyThreadNavigation", "ReplyTakeNavigation"),
    ("ReplyThreadHost", "ReplyTakeHost"),
    ("ReplyThreadView", "ReplyTakeView"),
    ("CommentThreadItem", "CommentTakeItem"),
    ("CommentThreading", "CommentTakeTree"),
    # Domain / data
    ("VideoFeedPage", "ShotFeedPage"),
    ("VideoPublishProgress", "ShotPublishProgress"),
    ("VideoPublishOutcome", "ShotPublishOutcome"),
    ("VideoDraftSummary", "ShotDraftSummary"),
    ("VideoDraftPayload", "ShotDraftPayload"),
    ("VideoDraft", "ShotDraft"),
    ("createAndPublishThread", "createAndPublishTake"),
    ("createAndPublishVideo", "createAndPublishShot"),
    ("waitForProcessedThreadImages", "waitForProcessedTakeImages"),
    ("processedThreadImageCount", "processedTakeImageCount"),
    ("waitForVideoTerminalStatus", "waitForShotTerminalStatus"),
    ("createThreadPost", "createTakePost"),
    ("createVideoPost", "createShotPost"),
    ("uploadThreadAttachments", "uploadTakeAttachments"),
    ("fetchThreadPosts", "fetchTakePosts"),
    ("fetchVideoPosts", "fetchShotPosts"),
    ("loadThreadPosts", "loadTakePosts"),
    ("loadVideoPosts", "loadShotPosts"),
    ("userThreadPosts", "userTakePosts"),
    ("userVideoPosts", "userShotPosts"),
    ("fetchThreads", "fetchTakes"),
    ("fetchVideos", "fetchShots"),
    ("makeThreadsFeedViewModel", "makeTakesFeedViewModel"),
    ("makeVideoFeedViewModel", "makeShotFeedViewModel"),
    ("threadPublishGeneration", "takePublishGeneration"),
    ("videoPublishGeneration", "shotPublishGeneration"),
    ("noteThreadPublished", "noteTakePublished"),
    ("noteVideoPublished", "noteShotPublished"),
    ("upsertVideoDraft", "upsertShotDraft"),
    ("fetchVideoDrafts", "fetchShotDrafts"),
    ("deleteVideoDraft", "deleteShotDraft"),
    ("loadVideoDraft", "loadShotDraft"),
    ("fetchVideoModel", "fetchShotModel"),
    ("enforceVideoDraftLimit", "enforceShotDraftLimit"),
    ("saveVideoDraft", "saveShotDraft"),
    ("beginVideoDraft", "beginShotDraft"),
    ("onOpenVideoDraft", "onOpenShotDraft"),
    ("removeThreadPost", "removeTakePost"),
    ("threadedComments", "takeComments"),
    ("videoFeedStyle", "shotFeedStyle"),
    ("video_feed_native", "shot_feed_native"),
    ("threadPosts", "takePosts"),
    ("videoPosts", "shotPosts"),
    ("threadCount", "takeCount"),
    ("videoCount", "shotCount"),
    ('"thread_count"', '"take_count"'),
    ('"video_count"', '"shot_count"'),
    ("updateThread(", "updateTake("),
    ("func updateThread", "func updateTake"),
    ("PostUseCaseVideoPublishTests", "PostUseCaseShotPublishTests"),
    # PostType enum cases & API strings (after type renames)
    ('postType: "thread"', 'postType: "take"'),
    ('postType: "video"', 'postType: "shot"'),
    ("postType == .thread", "postType == .take"),
    ("postType == .video", "postType == .shot"),
    ("post.postType == .thread", "post.postType == .take"),
    ("post.postType == .video", "post.postType == .shot"),
    ("feedItem.post.postType == .thread", "feedItem.post.postType == .take"),
    ("feedItem.post.postType == .video", "feedItem.post.postType == .shot"),
    ("postType: .thread", "postType: .take"),
    ("postType: .video", "postType: .shot"),
    ("case thread\n", "case take\n"),
    ("case video\n", "case shot\n"),
    (".thread:", ".take:"),
    (".video:", ".shot:"),
    ("== .thread", "== .take"),
    ("== .video", "== .shot"),
    ("AppTab.threads", "AppTab.takes"),
    ("AppTab.video", "AppTab.shots"),
    ("ProfilePostTab.threads", "ProfilePostTab.takes"),
    ("ProfilePostTab.videos", "ProfilePostTab.shots"),
    ("initialTab: .threads", "initialTab: .takes"),
    ("initialTab: .videos", "initialTab: .shots"),
    ("case .threads", "case .takes"),
    ("case .videos", "case .shots"),
    ("uploadVideo", "uploadShot"),
    # DTO guards
    ('== "thread"', '== "take"'),
    ('== "video"', '== "shot"'),
    ('posts/threads', 'posts/takes'),
    ('posts/videos', 'posts/shots'),
    ("VideoDrafts", "ShotDrafts"),
]

# UI string replacements (Presentation + Info.plist handled separately)
UI_REPLACEMENTS = [
    ("Loading threads...", "Loading takes..."),
    ("No threads yet", "No takes yet"),
    ("Loading videos...", "Loading shots..."),
    ("New Thread", "New Take"),
    ("Edit Thread", "Edit Take"),
    ("New Video", "New Shot"),
    ("Edit video", "Edit shot"),
    ('Tab("Threads"', 'Tab("Takes"'),
    ('Tab("Video"', 'Tab("Shots"'),
    ('title: "Threads"', 'title: "Takes"'),
    ('title: "Videos"', 'title: "Shots"'),
    ("Відео-чернетка", "Shot draft"),
]


def apply_replacements(text: str, path: Path) -> str:
    if is_technical_file(path):
        # Only apply upload/API renames that don't touch VideoClip etc. — minimal for technical files
        return text
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    if "/Presentation/" in str(path) or "/App/" in str(path):
        for old, new in UI_REPLACEMENTS:
            text = text.replace(old, new)
    return text


def fix_post_type_init(text: str) -> str:
    pattern = r"enum PostType: String, Codable, Sendable \{\n    case take\n    case shot\n\n    init\(rawValue: String\) \{\n        switch rawValue\.lowercased\(\) \{[^}]+\}\n    \}\n\}"
    replacement = '''enum PostType: String, Codable, Sendable {
    case take
    case shot

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "shot", "video":
            self = .shot
        case "take", "thread":
            self = .take
        default:
            self = .take
        }
    }
}'''
    if "enum PostType" in text and "case take" in text:
        text = re.sub(pattern, replacement, text, count=1)
    return text


def fix_post_dto_guards(text: str) -> str:
    if "PostDTO" not in text:
        return text
    text = text.replace(
        'guard postType.lowercased() == "take" else { return [] }',
        'guard postType.lowercased() == "take" || postType.lowercased() == "thread" else { return [] }',
    )
    text = text.replace(
        'guard postType.lowercased() == "shot",',
        'guard (postType.lowercased() == "shot" || postType.lowercased() == "video"),',
    )
    return text


def fix_app_tab_enum(text: str) -> str:
    if "private enum AppTab" not in text:
        return text
    text = re.sub(
        r"private enum AppTab: Hashable \{\n    case threads\n    case video\n",
        "private enum AppTab: Hashable {\n    case takes\n    case shots\n",
        text,
    )
    text = re.sub(
        r"private enum AppTab: Hashable \{\n    case takes\n    case shots\n    case create",
        "private enum AppTab: Hashable {\n    case takes\n    case shots\n    case create",
        text,
    )
    return text


def fix_profile_tab_enum(text: str) -> str:
    if "enum ProfilePostTab" not in text:
        return text
    return text.replace(
        """enum ProfilePostTab: String, CaseIterable, Sendable {
    case takes
    case shots
}""",
        """enum ProfilePostTab: String, CaseIterable, Sendable {
    case takes
    case shots
}""",
    ).replace(
        """enum ProfilePostTab: String, CaseIterable, Sendable {
    case threads
    case videos
}""",
        """enum ProfilePostTab: String, CaseIterable, Sendable {
    case takes
    case shots
}""",
    )


def main() -> None:
    changed: list[str] = []
    for path in ROOT.rglob("*.swift"):
        if not should_process(path):
            continue
        original = path.read_text(encoding="utf-8")
        updated = apply_replacements(original, path)
        if path.name == "Post.swift":
            updated = fix_post_type_init(updated)
        if path.name == "PostDTO.swift":
            updated = fix_post_dto_guards(updated)
        if path.name == "MainTabView.swift":
            updated = fix_app_tab_enum(updated)
        if path.name == "UserProfile.swift":
            updated = fix_profile_tab_enum(updated)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed.append(str(path.relative_to(ROOT.parent)))
    print(f"Updated {len(changed)} Swift files")


if __name__ == "__main__":
    main()
