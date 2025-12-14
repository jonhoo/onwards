#[allow(unused_imports)]
use tracing::{debug, error, info, trace, warn};

use axum::{
    extract::Path,
    response::{AppendHeaders, IntoResponse, Redirect},
    routing::get,
    Router,
};
use http::{header::CACHE_CONTROL, StatusCode};
use tower_http::limit::RequestBodyLimitLayer;

fn forwards_to(short: &str) -> Option<&'static str> {
    Some(match short {
        // This is where you add shortlinks!
        //
        // Note that "root" is special -- it is also where / will redirect.
        "root" => "https://rust-for-rustaceans.com",

        // All your other shortlinks go here:
        "youtube" => "https://www.youtube.com/@jonhoo",

        // Chapter 1 (foundations)
        "places" => "https://www.ralfj.de/blog/2024/08/14/places.html",
        "tmp-scopes" => {
            "https://doc.rust-lang.org/nightly/reference/destructors.html#temporary-scopes"
        }

        // Chapter 2 (types)
        "captures" => "https://blog.rust-lang.org/2024/09/05/impl-trait-capture-rules/",

        // Chapter 3 (designing interfaces)
        "dyn-compat" => "https://internals.rust-lang.org/t/object-safety-is-a-terrible-term/21025",
        "rfc1105" => "https://rust-lang.github.io/rfcs/1105-api-evolution.html",
        "semver" => "https://doc.rust-lang.org/cargo/reference/semver.html",
        "semver-check" => "https://github.com/obi1kenobi/cargo-semver-checks",

        // Chapter 4 (error handling)
        "downcast-risk" => "https://github.com/rust-lang/rfcs/pull/2895#discussion_r1894674526",
        "rfc2895" => "https://github.com/rust-lang/rfcs/pull/2895",
        "cf-unwrap" => "https://blog.cloudflare.com/18-november-2025-outage/#memory-preallocation",
        "try" => "https://github.com/rust-lang/rust/issues/84277",
        "try-blocks" => "https://github.com/rust-lang/rust/issues/31436",

        // Chapter 6 (testing)
        "test-builder" => "https://jmmv.dev/2020/12/builder-pattern-for-tests.html",

        // Chapter 9 (unsafe)
        "const-mut" => "https://github.com/rust-lang/unsafe-code-guidelines/issues/257",

        // Chapter 12 (no-std)
        "std-prelude" => "https://www.reddit.com/r/rust/comments/1hs6spy/psa_for_std_feature_in_no_std_libraries/",

        // Please preserve these two for attribution :)
        "about" => "https://github.com/jonhoo/onwards",
        "humans.txt" => "https://thesquareplanet.com",

        // Anything else is a 404
        _ => return None,
    })
}

pub async fn new() -> Router {
    Router::new()
        .route("/", get(root))
        .route("/{short}", get(forward))
        .layer(RequestBodyLimitLayer::new(1024))
}

async fn root() -> Redirect {
    Redirect::permanent(forwards_to("root").expect("root is always set"))
}

async fn forward(Path(short): Path<String>) -> Result<impl IntoResponse, StatusCode> {
    let Some(target) = forwards_to(&short) else {
        return Err(StatusCode::NOT_FOUND);
    };

    Ok((
        AppendHeaders([(CACHE_CONTROL, "max-age=86400, stale-if-error=31536000")]),
        Redirect::permanent(target),
    ))
}
