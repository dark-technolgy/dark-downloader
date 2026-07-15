#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

pub trait CommandNoWindow {
    fn no_window(self) -> Self;
}

impl CommandNoWindow for std::process::Command {
    fn no_window(mut self) -> Self {
        #[cfg(target_os = "windows")]
        self.creation_flags(0x08000000);
        self
    }
}

impl CommandNoWindow for tokio::process::Command {
    fn no_window(mut self) -> Self {
        #[cfg(target_os = "windows")]
        self.creation_flags(0x08000000);
        self
    }
}
