mod containers;

use tracing_subscriber::{layer::SubscriberExt as _, util::SubscriberInitExt as _};

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .with(
            tracing_subscriber::EnvFilter::builder()
                .with_default_directive(tracing::level_filters::LevelFilter::INFO.into())
                .from_env_lossy(),
        )
        .init();

    let chain = containers::Chain::new("localnet-chain").await?;
    tracing::info!(%chain.rpc);
    let ipfs = containers::Ipfs::new("localnet-ipfs").await?;
    tracing::info!(%ipfs.url);
    let postgres = containers::Postgres::new("localnet-postgres").await?;
    tracing::info!(%postgres.url);
    // TODO: mine block
    let graph_node =
        containers::GraphNode::new("localnet-graph-node", &postgres.url, &ipfs.url, &chain.rpc)
            .await?;

    let sigint = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())
            .expect("install SIGINT handler")
            .recv()
            .await;
    };
    let sigterm = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .unwrap()
            .recv()
            .await;
    };
    tokio::select! {
        _ = sigint => {},
        _ = sigterm => {},
    };
    Ok(())
}
