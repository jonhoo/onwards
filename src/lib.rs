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

        // Chapter 3 (designing interfaces)
        "dyn-compat" => "https://internals.rust-lang.org/t/object-safety-is-a-terrible-term/21025",

        // Chapter 9 (unsafe)
        "const-mut" => "https://github.com/rust-lang/unsafe-code-guidelines/issues/257",

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
