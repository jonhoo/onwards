#[allow(unused_imports)]
use tracing::{debug, error, info, trace, warn};

use axum::{
    extract::Path,
    response::{AppendHeaders, IntoResponse, Redirect},
    routing::get,
    Router,
};
use http::{header::CACHE_CONTROL, StatusCode};
use phf::phf_map;
use tower_http::limit::RequestBodyLimitLayer;

static FORWARDS: phf::Map<&'static str, &'static str> = phf_map! {
    // This is where you add shortlinks!
    //
    // Note that "root" is special -- it is also where / will redirect.
    "root" => "https://rust-for-rustaceans.com",

    // All your other shortlinks go here:
    "youtube" => "https://www.youtube.com/@jonhoo",

    // Please preserve these two for attribution :)
    "about" => "https://github.com/jonhoo/onwards",
    "humans.txt" => "https://thesquareplanet.com",
};

pub async fn new() -> Router {
    Router::new()
        .route("/", get(root))
        .route("/{short}", get(forward))
        .layer(RequestBodyLimitLayer::new(1024))
}

async fn root() -> Redirect {
    Redirect::permanent(FORWARDS["root"])
}

async fn forward(Path(short): Path<String>) -> Result<impl IntoResponse, StatusCode> {
    let Some(target) = FORWARDS.get(&*short) else {
        return Err(StatusCode::NOT_FOUND);
    };

    Ok((
        AppendHeaders([(CACHE_CONTROL, "max-age=86400, stale-if-error=31536000")]),
        Redirect::permanent(target),
    ))
}
