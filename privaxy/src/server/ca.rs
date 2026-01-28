use rcgen::{
    BasicConstraints, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair,
    KeyUsagePurpose,
};
use std::time::{Duration, SystemTime};

const ORGANIZATION_NAME: &str = "Privaxy";

/// Generates a CA certificate and private key using pure Rust (rcgen).
/// Returns (PEM Certificate, PEM Private Key)
pub fn make_ca_certificate() -> (String, String) {
    let mut params = CertificateParams::default();

    // Set validity: 3650 days from now (approx 10 years)
    let now = SystemTime::now();
    params.not_before = now.into();
    params.not_after = (now + Duration::from_secs(3650 * 24 * 60 * 60)).into();

    // Set Subject/Issuer name
    let mut dn = DistinguishedName::new();
    dn.push(DnType::CountryName, "US");
    dn.push(DnType::StateOrProvinceName, "CA");
    dn.push(DnType::OrganizationName, ORGANIZATION_NAME);
    dn.push(DnType::CommonName, ORGANIZATION_NAME);
    params.distinguished_name = dn;

    // Configure as CA
    params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);

    // Set Key Usages
    params.key_usages = vec![
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
        KeyUsagePurpose::DigitalSignature,
    ];

    // Generate KeyPair (uses Ring/Webpki-roots compatible logic)
    let key_pair = KeyPair::generate().unwrap();

    // Create the certificate
    let cert = params.self_signed(&key_pair).unwrap();

    (cert.pem(), key_pair.serialize_pem())
}
