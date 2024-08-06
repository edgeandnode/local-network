use axum::{
    http::{HeaderMap, HeaderName, HeaderValue},
    routing,
};
use std::{
    net::{Ipv4Addr, SocketAddr},
    time::Duration,
};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let router = axum::Router::new().route(
        "/subgraphs/id/QmfVaeTxHGQVtEc9hKPMdtvQeaFYPUSfGWr8HXU8rSsB49",
        routing::post(handle_query),
    );
    let addr = SocketAddr::new(std::net::IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0)), 8001);
    let listener = TcpListener::bind(addr).await?;
    println!("listening on {}", addr);
    axum::serve(listener, router.into_make_service()).await?;
    anyhow::bail!("server stopped");
}

async fn handle_query() -> (HeaderMap, &'static str) {
    tokio::time::sleep(Duration::from_millis(200)).await;
    let body = r#"{"data": {}}"#;
    let headers = HeaderMap::from_iter([(
        HeaderName::from_static("graph-attestable"),
        HeaderValue::from_static("true"),
    )]);
    (headers, body)
}
