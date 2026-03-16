use axum::{
    extract::Request,
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;

use crate::config::Config;

/// Google's JWKS endpoint for Firebase Auth tokens
const GOOGLE_JWKS_URL: &str =
    "https://www.googleapis.com/service_account/v1/metadata/jwk/securetoken@system.gserviceaccount.com";

/// How long to cache JWKS keys
const JWKS_CACHE_TTL_SECS: u64 = 3600; // 1 hour

/// Cached JWKS keys
pub struct JwksCache {
    keys: HashMap<String, DecodingKey>,
    fetched_at: Instant,
}

/// Shared JWKS cache state
pub type SharedJwksCache = Arc<RwLock<Option<JwksCache>>>;

/// Create a new empty JWKS cache
pub fn new_jwks_cache() -> SharedJwksCache {
    Arc::new(RwLock::new(None))
}

/// Authenticated device info extracted from headers
#[derive(Clone, Debug)]
pub struct AuthDevice {
    pub device_id: String,
    pub firebase_uid: Option<String>,
}

/// Firebase JWT claims we care about
#[derive(Debug, Deserialize)]
struct FirebaseClaims {
    sub: String,
    // iss and aud are checked by the Validation config
}

/// JWKS response from Google
#[derive(Debug, Deserialize)]
struct JwksResponse {
    keys: Vec<JwkKey>,
}

/// Individual JWK key
#[derive(Debug, Deserialize)]
struct JwkKey {
    kid: String,
    n: String,
    e: String,
}

/// Fetch JWKS from Google and return a map of kid -> DecodingKey
async fn fetch_jwks() -> Result<HashMap<String, DecodingKey>, String> {
    let resp = reqwest::get(GOOGLE_JWKS_URL)
        .await
        .map_err(|e| format!("Failed to fetch JWKS: {}", e))?;

    let jwks: JwksResponse = resp
        .json()
        .await
        .map_err(|e| format!("Failed to parse JWKS: {}", e))?;

    let mut keys = HashMap::new();
    for key in jwks.keys {
        match DecodingKey::from_rsa_components(&key.n, &key.e) {
            Ok(dk) => {
                keys.insert(key.kid, dk);
            }
            Err(e) => {
                tracing::warn!("Skipping JWK kid={}: {}", key.kid, e);
            }
        }
    }

    if keys.is_empty() {
        return Err("No valid keys in JWKS response".to_string());
    }

    Ok(keys)
}

/// Get a decoding key for the given kid, fetching/refreshing JWKS as needed
async fn get_decoding_key(
    cache: &SharedJwksCache,
    kid: &str,
) -> Result<DecodingKey, String> {
    // Try cache first
    {
        let guard = cache.read().await;
        if let Some(ref cached) = *guard {
            if cached.fetched_at.elapsed().as_secs() < JWKS_CACHE_TTL_SECS {
                if let Some(key) = cached.keys.get(kid) {
                    return Ok(key.clone());
                }
            }
        }
    }

    // Cache miss or expired — fetch fresh keys
    let keys = fetch_jwks().await?;

    let result = keys.get(kid).cloned();

    // Update cache
    {
        let mut guard = cache.write().await;
        *guard = Some(JwksCache {
            keys,
            fetched_at: Instant::now(),
        });
    }

    result.ok_or_else(|| format!("No JWKS key found for kid={}", kid))
}

/// Validate a Firebase ID token and return the uid (sub claim)
async fn validate_firebase_token(
    token: &str,
    project_id: &str,
    cache: &SharedJwksCache,
) -> Result<String, String> {
    // Decode the header to get the kid
    let header =
        decode_header(token).map_err(|e| format!("Invalid JWT header: {}", e))?;

    let kid = header
        .kid
        .ok_or_else(|| "JWT missing kid in header".to_string())?;

    if header.alg != Algorithm::RS256 {
        return Err(format!("Unexpected JWT algorithm: {:?}", header.alg));
    }

    // Get the decoding key
    let decoding_key = get_decoding_key(cache, &kid).await?;

    // Build validation
    let expected_issuer = format!("https://securetoken.google.com/{}", project_id);
    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&[project_id]);
    validation.set_issuer(&[&expected_issuer]);
    validation.validate_exp = true;

    // Decode and validate
    let token_data = decode::<FirebaseClaims>(token, &decoding_key, &validation)
        .map_err(|e| format!("JWT validation failed: {}", e))?;

    let uid = token_data.claims.sub;
    if uid.is_empty() {
        return Err("JWT sub claim is empty".to_string());
    }

    Ok(uid)
}

/// Returns true if the token looks like a JWT (has exactly 2 dots separating 3 parts)
fn looks_like_jwt(token: &str) -> bool {
    token.chars().filter(|&c| c == '.').count() == 2
}

/// Middleware that validates either a Firebase ID token or the legacy shared secret
pub async fn auth_middleware(
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let config = request
        .extensions()
        .get::<Arc<Config>>()
        .cloned()
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;

    let jwks_cache = request
        .extensions()
        .get::<SharedJwksCache>()
        .cloned()
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;

    // Check Authorization header
    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if !auth_header.starts_with("Bearer ") {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let token = &auth_header[7..];

    // Extract device ID (used for both auth paths)
    let device_id = request
        .headers()
        .get("x-device-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

    let auth_device = if looks_like_jwt(token) {
        // Try Firebase ID token validation
        match validate_firebase_token(token, &config.firebase_project_id, &jwks_cache).await {
            Ok(uid) => {
                tracing::debug!("Firebase auth success: uid={}, device={}", uid, device_id);
                AuthDevice {
                    device_id,
                    firebase_uid: Some(uid),
                }
            }
            Err(e) => {
                tracing::warn!("Firebase token validation failed: {}", e);
                return Err(StatusCode::UNAUTHORIZED);
            }
        }
    } else {
        // Legacy shared secret auth
        match &config.backend_secret {
            Some(secret) if token == secret => {
                tracing::debug!("Legacy secret auth success: device={}", device_id);
                AuthDevice {
                    device_id,
                    firebase_uid: None,
                }
            }
            _ => {
                tracing::warn!("Legacy auth failed: invalid or unconfigured secret");
                return Err(StatusCode::UNAUTHORIZED);
            }
        }
    };

    let mut request = request;
    request.extensions_mut().insert(auth_device);

    Ok(next.run(request).await)
}
