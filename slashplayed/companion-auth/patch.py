#!/usr/bin/env python3
"""Patch the pinned Slashplayed 1.6.1 Windows host without modifying the device kit."""
from pathlib import Path
import sys

root = Path(sys.argv[1])
vendor = root / "apps/companion-rs/vendor/isideload/src"
def replace(path, old, new):
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise SystemExit(f"Unexpected source in {path}: {old[:80]!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")

g = vendor / "auth/grandslam.rs"
replace(g, 'headers.insert("Content-Type", HeaderValue::from_static("text/x-xml-plist"));',
           'headers.insert("Content-Type", HeaderValue::from_static("text/xml"));')
# Preserve Accept, JSON headers, TLS validation and existing Apple authentication.
# Do not include raw authentication response bodies in parse error reports.
replace(g, 'use plist_macro::pretty_print_dictionary;\n', '')
replace(g, '.context("Failed to parse grandslam response plist")\n            .attach_with(|| resp.clone())?;',
           '.context("Failed to parse grandslam response plist")?;')
replace(g, 'report!("grandslam response missing \'Response\'")\n                    .attach(pretty_print_dictionary(&dict))',
           'report!("grandslam response missing \'Response\'")')
replace(g, '            .http1_title_case_headers()',
           '            .connect_timeout(std::time::Duration::from_secs(20))\n'
           '            .timeout(std::time::Duration::from_secs(60))\n'
           '            .http1_title_case_headers()')
# Rebuild only the read-only listDevices request on transient transport failures;
# never replay login, 2FA, certificate creation/revocation, or other mutations.
d = vendor / "dev/developer_session.rs"
replace(d, '        let text = self\n            .client\n            .post(url)?',
'''        let list_only = url.split('?').next().is_some_and(|p| p.ends_with("/listDevices.action"));
        let mut attempt = 0;
        let response = loop {
            attempt += 1;
            let result = self.client.post(url)?''')
replace(d, '''            .send()
            .await?
            .error_for_status()
            .context("Developer request failed")?''',
'''            .send()
            .await;
            #[cfg(not(feature = "wasm"))]
            if list_only && attempt < 3 && match &result {
                Ok(r) => matches!(r.status().as_u16(), 502 | 503 | 504),
                Err(reqwest_middleware::Error::Reqwest(e)) => e.is_connect() || e.is_timeout(),
                Err(_) => false,
            } {
                tokio::time::sleep(std::time::Duration::from_secs(attempt)).await;
                continue;
            }
            break result.context("Failed to send developer request")?;
        };
        let text = response.error_for_status().context("Developer request failed")?''')
# Ensure tokio's native timers are explicitly enabled. Feature change requires no
# new dependency or lockfile package.
cargo = root / "apps/companion-rs/vendor/isideload/Cargo.toml"
replace(cargo, 'tokio = { version = "1.49" }', 'tokio = { version = "1.49", features = ["time"] }')
# Verify exactly the relevant wire values and guard against accidental header drift.
with g.open(encoding="utf-8") as f:
    source = f.read()
assert 'headers.insert("Content-Type", HeaderValue::from_static("text/xml"));' in source
assert 'headers.insert("Content-Type", HeaderValue::from_static("application/json"));' in source
print("Applied Windows auth compatibility patch; no credentials used")
