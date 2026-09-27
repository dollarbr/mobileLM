//! Minimal `dlopen`/`dlsym`, so a binding to a native runtime is *loaded* rather
//! than *linked*.
//!
//! Why this exists, concretely: `liblitert-lm.so` is 39 MB and aarch64. Linking
//! against it would mean the crate only builds where that exact file is next to
//! the binary, so `cargo test` could not run on a laptop, and an app would fail
//! to *start* rather than report that the runtime is missing. Loading it instead
//! makes "the runtime is not there" an ordinary error value that the probe can
//! print and the UI can show.
//!
//! This is `libloading` in about a hundred lines, which is worth it here: the
//! probe in this same crate has to run on a bare `adb shell` with nothing
//! alongside it, so every dependency is a way for the thing that diagnoses the
//! device to fail to build for the device.
//!
//! Safety: `Lib` owns a loader handle and frees nothing on drop, deliberately.
//! See [`Lib::open`].

use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlerror() -> *const c_char;
}

/// `RTLD_NOW | RTLD_LOCAL`. `RTLD_NOW` on purpose: a missing symbol then fails
/// here, with a name, instead of at the first inference call on a phone with a
/// model half-loaded.
const RTLD_NOW: c_int = 2;
const RTLD_LOCAL: c_int = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SymbolMissing {
    pub name: String,
}

impl std::fmt::Display for SymbolMissing {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "missing symbol {}", self.name)
    }
}

impl std::error::Error for SymbolMissing {}

/// An open shared object. Not closed on drop: unloading a runtime while a handle
/// into it is still alive is a use-after-free, and the process is about to exit
/// or has already served its purpose anyway. The OS reclaims it.
pub struct Lib {
    handle: *mut c_void,
    path: String,
}

// A loader handle is process-global state, not thread-local.
unsafe impl Send for Lib {}
unsafe impl Sync for Lib {}

impl std::fmt::Debug for Lib {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Lib").field("path", &self.path).finish()
    }
}

fn last_error() -> String {
    // Safety: dlerror returns NULL or a NUL-terminated string owned by the
    // loader, valid until the next dl* call on this thread.
    unsafe {
        let p = dlerror();
        if p.is_null() {
            String::new()
        } else {
            std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
        }
    }
}

impl Lib {
    /// Open a shared object, keeping the loader's own message on failure.
    ///
    /// The distinction it preserves is the one that matters on a phone: "no such
    /// file" and "found, but the linker namespace forbids it" are completely
    /// different verdicts, and the loader's wording is the only thing that tells
    /// them apart.
    pub fn open(path: &str) -> Result<Self, String> {
        let c = CString::new(path).map_err(|_| "path contains a NUL byte".to_string())?;
        // Safety: `c` is a valid NUL-terminated string for the duration.
        let handle = unsafe { dlopen(c.as_ptr(), RTLD_NOW | RTLD_LOCAL) };
        if handle.is_null() {
            return Err(last_error());
        }
        Ok(Self {
            handle,
            path: path.to_string(),
        })
    }

    /// Resolve one symbol to a typed function pointer.
    ///
    /// # Safety
    /// `T` must be the exact signature the symbol was compiled with. Nothing here
    /// can check that: a mismatch is undefined behaviour, not an error. The
    /// signatures in `mobilelm-litert` carry the header line they were
    /// transcribed from for exactly this reason.
    pub unsafe fn fn_ptr<T: Copy>(&self, name: &str) -> Result<T, SymbolMissing> {
        let c = CString::new(name).map_err(|_| SymbolMissing {
            name: name.to_string(),
        })?;
        let p = unsafe { dlsym(self.handle, c.as_ptr()) };
        if p.is_null() {
            return Err(SymbolMissing {
                name: name.to_string(),
            });
        }
        // `transmute` refuses a generic T (it is dependently sized), so this goes
        // through `transmute_copy`, which for a same-sized T is the identical bit
        // pattern. It also inserts a runtime size check, so a caller that asks for
        // a wrongly-sized type gets a panic rather than silent corruption.
        Ok(unsafe { std::mem::transmute_copy::<*mut std::os::raw::c_void, T>(&p) })
    }

    pub fn path(&self) -> &str {
        &self.path
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opening_something_that_does_not_exist_reports_it() {
        let e = Lib::open("/definitely/not/here.so").unwrap_err();
        assert!(!e.is_empty());
    }

    #[test]
    fn a_real_library_loads_and_its_symbols_resolve() {
        // libc is present on every platform this runs on, which makes it the one
        // library that can be asserted on without shipping a fixture.
        let name = if cfg!(target_os = "android") || cfg!(target_os = "linux") {
            "libc.so.6"
        } else {
            "libSystem.B.dylib"
        };
        let Ok(lib) = Lib::open(name) else {
            // Android resolves libc under a different soname; the probe test
            // covers the real thing on-device.
            return;
        };
        // `getpid` is in libc on Linux and on macOS too.
        let sym: unsafe extern "C" fn() -> i32 = unsafe { lib.fn_ptr("getpid") }.unwrap();
        // SAFETY: the signature matches libc's `pid_t getpid(void)`.
        let pid = unsafe { sym() };
        assert!(pid > 0);
    }

    #[test]
    fn a_missing_symbol_names_itself() {
        let lib = Lib::open("libc.so.6");
        let Ok(lib) = lib else { return };
        let e: Result<unsafe extern "C" fn(), _> = unsafe { lib.fn_ptr("no_such_symbol_xyz") };
        assert_eq!(e.unwrap_err().name, "no_such_symbol_xyz");
    }
}
