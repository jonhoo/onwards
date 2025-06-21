use http::StatusCode;
use reqwest::{redirect, Client};
use std::io;
use std::time::Duration;
use tokio::task::JoinHandle;

type ServerTaskHandle = JoinHandle<Result<(), io::Error>>;

const TESTRUN_SETUP_TIMEOUT: Duration = Duration::from_secs(5);

async fn init() -> (String, ServerTaskHandle) {
    let (tx, rx) = tokio::sync::oneshot::channel();
    let handle = tokio::spawn(async move {
        let app = onwards_api::new().await;
        let addr = std::net::SocketAddr::from(([127, 0, 0, 1], 0));
        let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
        let assigned_addr = listener.local_addr().unwrap();
        tx.send(assigned_addr).unwrap();
        axum::serve(listener, app.into_make_service()).await
    });
    let assigned_addr = tokio::time::timeout(TESTRUN_SETUP_TIMEOUT, rx)
        .await
        .expect("test setup to not have timed out")
        .expect("socket address to have been received from the channel");
    let app_addr = format!("http://localhost:{}", assigned_addr.port());
    (app_addr, handle)
}

#[tokio::test]
async fn root() {
    let (app, _) = init().await;
    let c = Client::builder()
        .redirect(redirect::Policy::none())
        .build()
        .unwrap();
    let implicit_root = c.get(&app).send().await.unwrap();
    assert_eq!(implicit_root.status(), StatusCode::PERMANENT_REDIRECT);
    let explicit_root = c.get(format!("{app}/root")).send().await.unwrap();
    assert_eq!(explicit_root.status(), StatusCode::PERMANENT_REDIRECT);
    assert_eq!(
        implicit_root.headers().get(http::header::LOCATION).unwrap(),
        explicit_root.headers().get(http::header::LOCATION).unwrap(),
    );
}

#[tokio::test]
async fn invalid_short() {
    let (app, _) = init().await;
    let c = Client::builder()
        .redirect(redirect::Policy::none())
        .build()
        .unwrap();
    let r = c.get(format!("{app}/not-about")).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn valid_short() {
    let (app, _) = init().await;
    let c = Client::builder()
        .redirect(redirect::Policy::none())
        .build()
        .unwrap();
    let r = c.get(format!("{app}/about")).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::PERMANENT_REDIRECT);
    assert_eq!(
        r.headers().get(http::header::LOCATION).unwrap(),
        "https://github.com/jonhoo/onwards"
    );
}
