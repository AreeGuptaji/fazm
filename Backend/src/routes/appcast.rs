use axum::{
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};
use serde::Deserialize;

const GITHUB_REPO: &str = "m13v/fazm";
const GITHUB_API: &str = "https://api.github.com";

#[derive(Deserialize)]
struct GitHubRelease {
    tag_name: String,
    published_at: String,
    body: Option<String>,
    assets: Vec<GitHubAsset>,
    prerelease: bool,
    draft: bool,
}

#[derive(Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
    size: u64,
}

/// GET /appcast.xml
/// Dynamically generates a Sparkle-compatible appcast from GitHub releases.
/// Stable (non-prerelease) items have no channel tag (visible to all).
/// Prerelease items get <sparkle:channel>staging</sparkle:channel>.
pub async fn appcast() -> Response {
    match generate_appcast().await {
        Ok(xml) => (
            StatusCode::OK,
            [
                (header::CONTENT_TYPE, "application/rss+xml; charset=utf-8"),
                (header::CACHE_CONTROL, "public, max-age=300"),
            ],
            xml,
        )
            .into_response(),
        Err(e) => {
            tracing::error!("Failed to generate appcast: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to generate appcast: {}", e),
            )
                .into_response()
        }
    }
}

async fn generate_appcast() -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let client = reqwest::Client::builder()
        .user_agent("fazm-backend/1.0")
        .build()?;

    let releases: Vec<GitHubRelease> = client
        .get(format!(
            "{}/repos/{}/releases?per_page=10",
            GITHUB_API, GITHUB_REPO
        ))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;

    let mut items = Vec::new();

    for release in &releases {
        if release.draft {
            continue;
        }

        // Find the .zip asset (not appcast.xml)
        let zip_asset = release
            .assets
            .iter()
            .find(|a| a.name.ends_with(".zip") && !a.name.to_lowercase().contains("appcast"));

        let zip_asset = match zip_asset {
            Some(a) => a,
            None => continue,
        };

        // Parse version from tag: v0.9.0+56-macos or v0.9.0+56-macos-staging
        let tag = &release.tag_name;
        let version_re =
            regex_lite::Regex::new(r"v?(\d+\.\d+\.\d+)(?:\+(\d+))?(?:-macos)?(?:-staging)?")
                .unwrap();

        let caps = match version_re.captures(tag) {
            Some(c) => c,
            None => continue,
        };

        let version = &caps[1];
        let build_number = if let Some(b) = caps.get(2) {
            b.as_str().to_string()
        } else {
            // Calculate from version: 0.9.0 -> 9000
            let parts: Vec<u64> = version.split('.').filter_map(|p| p.parse().ok()).collect();
            let bn = parts.iter().fold(0u64, |acc, &p| acc * 1000 + p);
            bn.to_string()
        };

        // Extract EdDSA signature from release body
        let ed_sig = release
            .body
            .as_deref()
            .and_then(|body| {
                let re =
                    regex_lite::Regex::new(r#"edSignature[\"=:]\s*[\"]*([A-Za-z0-9+/=]{40,})"#)
                        .ok()?;
                re.captures(body)
                    .and_then(|c| c.get(1))
                    .map(|m| m.as_str().to_string())
            })
            .unwrap_or_default();

        // Format pub date as RFC 2822
        let pub_date = format_rfc2822(&release.published_at);

        // Channel tag: stable releases have no channel (visible to all),
        // prereleases get staging channel
        let channel_tag = if release.prerelease {
            "\n      <sparkle:channel>staging</sparkle:channel>".to_string()
        } else {
            String::new()
        };

        // Build enclosure attributes
        let mut enclosure_attrs = format!(r#"url="{}""#, zip_asset.browser_download_url);
        if !ed_sig.is_empty() {
            enclosure_attrs.push_str(&format!(
                "\n                 sparkle:edSignature=\"{}\"",
                ed_sig
            ));
        }
        enclosure_attrs.push_str(&format!(
            "\n                 length=\"{}\"",
            zip_asset.size
        ));
        enclosure_attrs.push_str("\n                 type=\"application/octet-stream\"");

        items.push(format!(
            r#"    <item>
      <title>Version {version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{build_number}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>{channel_tag}
      <enclosure {enclosure_attrs}/>
    </item>"#,
        ));
    }

    let xml = format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Fazm</title>
    <link>https://github.com/m13v/fazm/releases</link>
    <description>Fazm Desktop Updates</description>
    <language>en</language>
{items}
  </channel>
</rss>"#,
        items = items.join("\n")
    );

    Ok(xml)
}

fn format_rfc2822(iso: &str) -> String {
    // Parse ISO 8601 (e.g. "2024-03-15T12:00:00Z") -> RFC 2822
    let normalized = iso.replace('Z', "+00:00");
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(&normalized) {
        dt.format("%a, %d %b %Y %H:%M:%S +0000").to_string()
    } else {
        iso.to_string()
    }
}
