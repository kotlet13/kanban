# Idea board capture fixture

`ideas-coffee.jpg` is the original Pexels photograph312418 by Chevanon Photography,
[source page](https://www.pexels.com/photo/close-up-of-coffee-cup-on-table-312418/),
[Pexels license](https://www.pexels.com/license/), checked13 October2026.
It is an isolated promotional capture input, outside Flutter runtime assets.
It contains no user photograph or installed profile data.

The capture harness imports the bytes through the real IdeaRepository normalizer
and cache, opens a real saved board through IdeasPage, then renders IdeaEditor.
The photo annotation and drawing are actual editable board elements, not image
overlays. Notes are separate editable sticky notes beside the photograph.
Only viewport pan/zoom is positioned for the capture. Output is an unmodified
720×1280 widget render; it is not a photograph of a physical device.

Use `ideas_board_screenshot_test.dart` in the isolated Android25 source snapshot
with `JIVIE_IDEA_CAPTURE_PHOTO` pointing here and `JIVIE_IDEA_CAPTURE_OUT` pointing
to a fresh QA directory, then `flutter test --no-pub` with the existing locked
dependencies. This tooling does not seed the installed app or create a new AAB.
The recorded source boundary and publication evidence are in
[the release note](../../../docs/release/IDEAS_BOARD_SCREENSHOT.md).
