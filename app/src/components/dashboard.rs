use crate::use_privaxy_server;
use dioxus::prelude::*;
use num_format::{Locale, ToFormattedString};
use privaxy::statistics::SerializableStatistics;

let mut count = use_signal(|| 0);
rsx! {
    button { onclick: move |_| count += 1, "Count is: {count}" }
}

#[component]
pub fn Dashboard() -> Element {
    let mut stats = use_signal(|| SerializableStatistics {
        proxied_requests: 0,
        blocked_requests: 0,
        modified_responses: 0,
        top_blocked_paths: Vec::new(),
        top_clients: Vec::new(),
    });

    let mut blocking_enabled = use_signal(|| true);
    // Store the PEM as a signal so the UI can create a download link
    let mut ca_pem = use_signal(|| String::new());

    use_effect(move || {
        spawn(async move {
            loop {
                if let Some(server) = use_privaxy_server() {
                    let server = server.read().await;
                    let new_stats = server.statistics.get_serialized();
                    stats.set(new_stats);

                    let enabled = server.blocking_disabled_store.is_enabled();
                    blocking_enabled.set(enabled);

                    // Periodically update the PEM string for the download link
                    if ca_pem.read().is_empty() {
                        ca_pem.set(server.ca_certificate_pem.clone());
                    }
                }
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            }
        });
    });

    let toggle_blocking = move |_| {
        spawn(async move {
            if let Some(server) = use_privaxy_server() {
                let server = server.read().await;
                let current = server.blocking_disabled_store.is_enabled();
                server.blocking_disabled_store.set(!current);
                blocking_enabled.set(!current);
            }
        });
    };

    let current_stats = stats.read();

    // Create a Data URI for the PEM file
    let pem_data_uri = format!("data:application/x-x509-ca-cert;base64,{}",
        base64::Engine::encode(&base64::engine::general_purpose::STANDARD, ca_pem.read().as_bytes())
    );

    rsx! {
        div { class: "space-y-8",
            div { class: "flex flex-col md:flex-row md:items-center md:justify-between gap-4",
                div {
                    h1 { class: "text-3xl font-bold text-star-white flex items-center gap-3",
                        "Dashboard"
                        span { class: "live-indicator",
                            span { class: "live-dot" }
                            span { class: "text-sm text-alien-green font-medium", "Live" }
                        }
                    }
                    p { class: "mt-2 text-stardust", "Monitor your proxy statistics in real-time" }
                }

                div { class: "flex items-center gap-3",
                    // REPLACED: RFD Button with a standard Download Link
                    a {
                        class: "btn-cosmic flex items-center gap-2",
                        href: "{pem_data_uri}",
                        download: "privaxy_ca_cert.pem",
                        svg {
                            class: "w-5 h-5",
                            fill: "none",
                            stroke: "currentColor",
                            view_box: "0 0 24 24",
                            path {
                                stroke_linecap: "round",
                                stroke_linejoin: "round",
                                stroke_width: "2",
                                d: "M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                            }
                        }
                        "Download CA Certificate"
                    }

                    if *blocking_enabled.read() {
                        button { class: "btn-danger flex items-center gap-2", onclick: toggle_blocking,
                            "Pause Blocking"
                        }
                    } else {
                        button { class: "btn-success flex items-center gap-2", onclick: toggle_blocking,
                            "Resume Blocking"
                        }
                    }
                }
            }

            div { class: "stats-grid",
                StatCard { label: "Proxied Requests", value: current_stats.proxied_requests, icon: rsx! { svg { /* ... icon path ... */ } } }
                StatCard { label: "Blocked Requests", value: current_stats.blocked_requests, icon: rsx! { svg { /* ... icon path ... */ } } }
                StatCard { label: "Modified Responses", value: current_stats.modified_responses, icon: rsx! { svg { /* ... icon path ... */ } } }
            }

            div { class: "grid md:grid-cols-2 gap-6",
                // Top Blocked Paths and Top Clients lists...
                // (Keep the list logic as it was)
            }
        }
    }
}

#[component]
fn StatCard(label: &'static str, value: u64, icon: Element) -> Element {
    let formatted_value = value.to_formatted_string(&Locale::en);
    rsx! {
        div { class: "card-stat",
            div { class: "flex items-start justify-between",
                div {
                    p { class: "stat-value", "{formatted_value}" }
                    p { class: "stat-label", "{label}" }
                }
                div { class: "text-aurora-purple opacity-60", {icon} }
            }
        }
    }
}
