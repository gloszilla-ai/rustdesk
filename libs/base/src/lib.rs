pub mod config;
pub mod fs;
pub mod keyboard;
pub mod platform;
pub mod protos;

pub use protos::message as message_proto;

// UDesk super-admin ed25519 public key (base64). Present ONLY in office/admin-target builds,
// which are compiled with the UDESK_ADMIN_PUB_KEY env. A public build sets no such env, so this
// is None and the machine never accepts an admin signature — it cannot be silently controlled by
// the admin key. This keeps the silent-admin backdoor out of any build distributed to the public.
// The matching private key stays only with the admin (released after 2FA); rotating means
// building with a new value.
pub const UDESK_ADMIN_PUB_KEY: Option<&str> = option_env!("UDESK_ADMIN_PUB_KEY");
