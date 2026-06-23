//! Rules for video downloads: a video-only (DASH) stream should be paired with
//! a separate audio track when one exists, so the user never gets silent video
//! on purpose. Dart uses the same policy in the quality picker; this module
//! documents and tests the logic for the Rust side of the stack.

/// Returns `true` when a separate audio download + mux should be used.
#[inline]
pub fn should_pair_separate_audio(
    is_video_only: bool,
    separate_audio_tracks_available: bool,
) -> bool {
    is_video_only && separate_audio_tracks_available
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pairs_when_both_flags_set() {
        assert!(should_pair_separate_audio(true, true));
        assert!(!should_pair_separate_audio(true, false));
        assert!(!should_pair_separate_audio(false, true));
        assert!(!should_pair_separate_audio(false, false));
    }
}
