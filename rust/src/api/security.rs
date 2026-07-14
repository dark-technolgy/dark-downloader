use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Key, Nonce,
};
use anyhow::{anyhow, Result};
use argon2::{password_hash::SaltString, Argon2};
use obfstr::obfstr;
use std::fs::File;
use std::io::{Read, Write};

pub struct SupabaseSecrets {
    pub url: String,
    pub anon_key: String,
}

pub fn rust_get_supabase_config() -> SupabaseSecrets {
    // Obfuscated fallback used ONLY for local/dev builds that do not pass
    // --dart-define=SUPABASE_URL / SUPABASE_ANON_KEY. Production (release.yml)
    // always injects the real keys via --dart-define, which override these.
    //
    // Project: dark-downloader-prod (ref `rptcqqohdnpciyohnekx`).
    // The anon key is a public, safe-to-ship JWT.
    SupabaseSecrets {
        url: obfstr!("https://rptcqqohdnpciyohnekx.supabase.co").to_string(),
        anon_key: obfstr!("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwdGNxcW9oZG5wY2l5b2huZWt4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxNjc2MDMsImV4cCI6MjA5Nzc0MzYwM30.WQmiKjq_VUajPQ9z9eCpqT1vs2JetH-31C-RFW0shGM").to_string(),
    }
}

pub fn rust_get_device_fingerprint() -> String {
    "rust_hwid_placeholder".to_string()
}

pub fn rust_sign_message(message: String, secret: String) -> String {
    use std::hash::{Hash, Hasher};
    let mut hasher = ahash::AHasher::default();
    message.hash(&mut hasher);
    secret.hash(&mut hasher);
    format!("{:x}", hasher.finish())
}

/// فحص سلامة التطبيق (كشف الروت وأدوات الاختراق)
pub fn rust_check_app_integrity() -> bool {
    #[cfg(target_os = "android")]
    {
        // 1. Anti-Root: Check for su binaries
        let su_paths = [
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/system/su",
            "/system/bin/.ext/.su",
            "/system/usr/we-need-root/su-backup",
            "/system/xbin/mu",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
            "/su/bin/su",
        ];
        for path in su_paths.iter() {
            if std::path::Path::new(path).exists() {
                return false; // Root detected
            }
        }

        // 2. Anti-Frida: Check for frida server files
        let frida_paths = [
            "/data/local/tmp/frida-server",
            "/data/local/tmp/re.frida.server",
        ];
        for path in frida_paths.iter() {
            if std::path::Path::new(path).exists() {
                return false; // Frida detected
            }
        }

        // 3. Anti-Tamper: Check maps for suspicious libraries
        if let Ok(maps) = std::fs::read_to_string("/proc/self/maps") {
            if maps.contains("frida") || maps.contains("xposed") || maps.contains("substrate") {
                return false;
            }
        }
    }

    true
}

pub fn rust_generate_secure_token(payload: String) -> String {
    use std::hash::{Hash, Hasher};
    let mut hasher = ahash::AHasher::default();
    payload.hash(&mut hasher);
    format!("{:x}", hasher.finish())
}

// --- Hidden Vault Functions ---

/// Derive a 256-bit key from a PIN/Password and a salt using Argon2
fn derive_vault_key(password: &str, salt: &[u8]) -> Result<[u8; 32]> {
    let mut key = [0u8; 32];
    let argon2 = Argon2::default();
    let salt_obj =
        SaltString::encode_b64(salt).map_err(|e| anyhow!("Salt encoding error: {}", e))?;

    // Simple derivation for vault key
    argon2
        .hash_password_into(password.as_bytes(), salt_obj.as_str().as_bytes(), &mut key)
        .map_err(|e| anyhow!("Key derivation failed: {}", e))?;

    Ok(key)
}

/// Encrypt a file and move it to the vault
pub fn vault_encrypt_file(
    source_path: String,
    target_path: String,
    password: String,
) -> Result<()> {
    let mut data = Vec::new();
    File::open(&source_path)?.read_to_end(&mut data)?;

    // Generate random salt (16 bytes) and nonce (12 bytes)
    let mut salt = [0u8; 16];
    let mut nonce_bytes = [0u8; 12];

    // Use rand::fill for straightforward byte generation
    rand::fill(&mut salt);
    rand::fill(&mut nonce_bytes);

    let key_bytes = derive_vault_key(&password, &salt)?;
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let encrypted_data = cipher
        .encrypt(nonce, data.as_ref())
        .map_err(|e| anyhow!("Encryption error: {}", e))?;

    // Write: SALT (16) + NONCE (12) + ENCRYPTED_DATA
    let mut out_file = File::create(&target_path)?;
    out_file.write_all(&salt)?;
    out_file.write_all(&nonce_bytes)?;
    out_file.write_all(&encrypted_data)?;

    // Delete original file after successful encryption
    let _ = std::fs::remove_file(source_path);

    Ok(())
}

/// Decrypt a file from the vault back to a usable location
pub fn vault_decrypt_file(vault_path: String, output_path: String, password: String) -> Result<()> {
    let mut file = File::open(&vault_path)?;

    let mut salt = [0u8; 16];
    let mut nonce_bytes = [0u8; 12];
    file.read_exact(&mut salt)?;
    file.read_exact(&mut nonce_bytes)?;

    let mut encrypted_data = Vec::new();
    file.read_to_end(&mut encrypted_data)?;

    let key_bytes = derive_vault_key(&password, &salt)?;
    let key = Key::<Aes256Gcm>::from_slice(&key_bytes);
    let cipher = Aes256Gcm::new(key);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let decrypted_data = cipher
        .decrypt(nonce, encrypted_data.as_ref())
        .map_err(|_| anyhow!("Decryption error: Incorrect password or corrupted file"))?;

    if let Some(parent) = std::path::Path::new(&output_path).parent() {
        std::fs::create_dir_all(parent)?;
    }

    File::create(output_path)?.write_all(&decrypted_data)?;

    // Remove the encrypted file from the vault after successful decryption
    let _ = std::fs::remove_file(vault_path);

    Ok(())
}
