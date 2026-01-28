use http::uri::Authority;
use rcgen::{
    CertificateParams, DnType, IsCa, KeyPair,
    KeyUsagePurpose, SanType, Certificate,
};
use rustls::ServerConfig;
use rustls_pki_types::{CertificateDer, PrivateKeyDer};
use std::{str::FromStr, sync::Arc};
use tokio::sync::Mutex;
use uluru::LRUCache;

const MAX_CACHED_CERTIFICATES: usize = 1_000;

#[derive(Clone)]
pub struct SignedWithCaCert {
    authority: Authority,
    pub server_configuration: Arc<ServerConfig>,
}

impl SignedWithCaCert {
    fn new(
        authority: Authority,
        ca_cert: &Certificate,
        ca_key: &KeyPair, // Explicitly pass the CA key
    ) -> Self {
        let host = authority.host();
        let common_name = if host.len() > 64 {
            "privaxy_cn_too_long.local"
        } else {
            host
        };

        // 2026 rcgen 0.13: Use new() to initialize params
        let mut params = CertificateParams::new(vec![host.to_string()]).unwrap();
        params.distinguished_name.push(DnType::CommonName, common_name);

        // Set Subject Alternative Names
        if let Ok(ip) = std::net::IpAddr::from_str(host) {
            params.subject_alt_names.push(SanType::IpAddress(ip));
        }

        params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
        ];
        params.is_ca = IsCa::NoCa;

        let key_pair = KeyPair::generate().unwrap();

        // 2026 FIX: signed_by now takes the CA key as the third argument directly
        let cert = params.signed_by(&key_pair, ca_cert, ca_key).unwrap();

        let cert_der = CertificateDer::from(cert.der().to_vec());
        let ca_der = CertificateDer::from(ca_cert.der().to_vec());
        let key_der = PrivateKeyDer::try_from(key_pair.serialize_der()).unwrap();

        let server_configuration = ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(vec![cert_der, ca_der], key_der)
            .expect("Failed to create rustls config");

        Self {
            authority,
            server_configuration: Arc::new(server_configuration),
        }
    }
}

#[derive(Clone)]
pub struct CertCache {
    cache: Arc<Mutex<LRUCache<SignedWithCaCert, MAX_CACHED_CERTIFICATES>>>,
    ca_cert: Arc<Certificate>,
    ca_key: Arc<KeyPair>, // Store the CA key separately
}

impl CertCache {
    pub fn new(ca_cert_pem: &str, ca_key_pem: &str) -> Self {
        let ca_key = KeyPair::from_pem(ca_key_pem).expect("Invalid CA Key");

        let mut params = CertificateParams::new(vec!["Privaxy CA".to_string()]).unwrap();
        params.is_ca = IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        params.distinguished_name.push(DnType::CommonName, "Privaxy CA");

        let ca_cert = params.self_signed(&ca_key).expect("Failed to sign CA");

        Self {
            cache: Arc::new(Mutex::new(LRUCache::default())),
            ca_cert: Arc::new(ca_cert),
            ca_key: Arc::new(ca_key),
        }
    }

    pub async fn get(&self, authority: Authority) -> SignedWithCaCert {
        let mut cache = self.cache.lock().await;
        if let Some(certificate) = cache.find(|cert| cert.authority == authority) {
            return certificate.clone();
        }

        let ca_cert = self.ca_cert.clone();
        let ca_key = self.ca_key.clone();
        let auth_clone = authority.clone();

        let certificate = tokio::task::spawn_blocking(move || {
            SignedWithCaCert::new(auth_clone, &ca_cert, &ca_key)
        })
        .await
        .expect("Cert gen task failed");

        cache.insert(certificate.clone());
        certificate
    }
}
