#![allow(non_snake_case)]
#[cfg(all(target_arch = "mips", target_endian = "little"))]
use portable_atomic as _;

use dioxus::prelude::*;
use privaxy::PrivaxyServer;
use std::sync::Arc;
use tokio::sync::RwLock;

mod components;

use components::dashboard::Dashboard;
use components::filters::Filters;
use components::nav::Navigation;
use components::requests::{start_request_listener, Requests};
use components::settings::{CustomFilters, Exclusions, Settings};

const STYLES_RAW: &str = include_str!("../assets/styles.css");
const RUST_LOG_ENV_KEY: &str = "RUST_LOG";

// Global state for the privaxy server
static PRIVAXY_SERVER: GlobalSignal<Option<Arc<RwLock<PrivaxyServer>>>> = Signal::global(|| None);

#[tokio::main]
async fn main() {
    let _ = std::fs::create_dir_all("/opt/etc/privaxy/public");
    // Initialize logging
    if std::env::var(RUST_LOG_ENV_KEY).is_err() {
        unsafe {
            std::env::set_var(RUST_LOG_ENV_KEY, "privaxy=info,privaxy_app=info");
        }
    }
    env_logger::init();

    #[cfg(feature = "liveview")]
    {
        use ::axum::routing::get;
        use ::axum::response::IntoResponse;

        let dioxus_router = dioxus::server::router(App);

        let app = ::axum::Router::new()
            .route("/dioxus/index.js", get(|| async {
                (
                    [(::axum::http::header::CONTENT_TYPE, "application/javascript")],
                    dioxus_server::prelude::index_js(),
                ).into_response()
            }))
            .merge(dioxus_router);

        let addr = std::net::SocketAddr::from(([0, 0, 0, 0], 8080));
        log::info!("Starting LiveView server on http://{}", addr);

        let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
        
        ::axum::serve(listener, app.into_make_service()).await.unwrap();
    }

    #[cfg(not(feature = "liveview"))]
    dioxus::launch(App);
}

#[derive(Debug, Clone, Routable, PartialEq)]
#[rustfmt::skip]
enum Route {
    #[layout(MainLayout)]
    #[route("/")]
    Dashboard {},
    #[route("/requests")]
    Requests {},
    #[nest("/settings")]
        #[layout(Settings)]
        #[route("/filters")]
        Filters {},
        #[route("/exclusions")]
        Exclusions {},
        #[route("/custom-filters")]
        CustomFilters {},
        #[end_layout]
    #[end_nest]
    #[end_layout]
    #[route("/:..route")]
    NotFound { route: Vec<String> },
}

#[component]
fn MainLayout() -> Element {
    // Start privaxy server on first render
    use_effect(move || {
        spawn(async move {
            if PRIVAXY_SERVER.read().is_none() {
                log::info!("Starting Privaxy server...");
                let server = privaxy::start_privaxy().await;
                log::info!("Privaxy server started on http://0.0.0.0:8100");
                *PRIVAXY_SERVER.write() = Some(Arc::new(RwLock::new(server)));
                
                // Start the global request listener
                start_request_listener();
            }
        });
    });

    rsx! {
        style { "{STYLES_RAW}" }
        
        div { class: "min-h-screen bg-galaxy",
            Navigation {}
            main { class: "container mx-auto px-4 sm:px-6 lg:px-8 py-8",
                Outlet::<Route> {}
            }
        }
    }
}

#[component]
fn NotFound(route: Vec<String>) -> Element {
    rsx! {
        div { class: "flex flex-col items-center justify-center min-h-[60vh] text-center",
            div { class: "text-8xl font-black text-transparent bg-clip-text bg-gradient-to-r from-nebula-pink via-nebula-purple to-cosmic-blue animate-pulse",
                "404"
            }
            h1 { class: "mt-6 text-3xl font-bold text-star-white",
                "Lost in Space"
            }
            p { class: "mt-4 text-lg text-stardust",
                "The page you're looking for doesn't exist in this galaxy."
            }
            Link {
                to: Route::Dashboard {},
                class: "mt-8 px-6 py-3 rounded-xl bg-gradient-to-r from-nebula-purple to-cosmic-blue text-star-white font-semibold hover:shadow-nebula transition-all duration-300",
                "Return to Dashboard"
            }
        }
    }
}

#[component]
fn App() -> Element {
    rsx! {
        document::Script { src: "/dioxus/index.js" } 
        Router::<Route> {}
    }
}

// Helper function to get the privaxy server
pub fn use_privaxy_server() -> Option<Arc<RwLock<PrivaxyServer>>> {
    PRIVAXY_SERVER.read().clone()
}
