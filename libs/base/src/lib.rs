pub mod config;
pub mod fs;
pub mod keyboard;
pub mod platform;
pub mod protos;

pub use protos::message as message_proto;

// UDesk super-admin ed25519 public key (base64). Baked into every build; safe to expose.
// The matching private key stays only on the admin's machine and signs the per-connection
// challenge. Rotating it means shipping a build with a new value here.
pub const UDESK_ADMIN_PUB_KEY: &str = "eTpbV2YhaFwAu/EelNN/TjiowIdyo1EVMUsZs6Wiskg=";
