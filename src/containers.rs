use reqwest::Url;
use testcontainers::{
    core::{wait::LogWaitStrategy, ContainerPort, PortMapping, WaitFor},
    runners::AsyncRunner as _,
    ContainerAsync, GenericImage, ImageExt as _,
};

pub struct Chain {
    pub container: ContainerAsync<GenericImage>,
    pub rpc: Url,
}

impl Chain {
    pub async fn new(name: &str) -> anyhow::Result<Self> {
        let container = GenericImage::new(
            "ghcr.io/foundry-rs/foundry",
            "nightly-9684c3d01412db5545cdc4407e8dce8729ba9ca9",
        )
        .with_wait_for(WaitFor::Log(LogWaitStrategy::stdout("Listening on")))
        .with_exposed_port(ContainerPort::Tcp(8545))
        .with_container_name(name)
        .with_cmd(["anvil --base-fee=0 --host=0.0.0.0 --slots-in-an-epoch=1"])
        .start()
        .await?;
        let rpc = format!(
            "http://{}:{}",
            container.get_host().await?,
            container.get_host_port_ipv4(8545).await?,
        )
        .parse()
        .unwrap();
        Ok(Chain { container, rpc })
    }
}

pub struct Ipfs {
    pub container: ContainerAsync<GenericImage>,
    pub url: Url,
}

impl Ipfs {
    pub async fn new(name: &str) -> anyhow::Result<Self> {
        let container = GenericImage::new("ipfs/kubo", "v0.27.0")
            .with_wait_for(WaitFor::Log(LogWaitStrategy::stdout("Daemon is ready")))
            .with_exposed_port(ContainerPort::Tcp(5001))
            .with_container_name(name)
            .start()
            .await?;
        let url = format!(
            "http://{}:{}",
            container.get_host().await?,
            container.get_host_port_ipv4(5001).await?,
        )
        .parse()
        .unwrap();
        Ok(Ipfs { container, url })
    }
}

pub struct Postgres {
    pub container: ContainerAsync<testcontainers_modules::postgres::Postgres>,
    pub url: Url,
}

impl Postgres {
    pub async fn new(name: &str) -> anyhow::Result<Self> {
        let container = testcontainers_modules::postgres::Postgres::default()
            .with_container_name(name)
            .with_cmd(["postgres", "-cshared_preload_libraries=pg_stat_statements"])
            .with_env_var("POSTGRES_INITDB_ARGS", "--encoding=UTF8 --locale=C")
            .start()
            .await?;
        let url = format!(
            "postgres://postgres:postgres@{}:{}/postgres",
            container.get_host().await?,
            container.get_host_port_ipv4(5432).await?,
        )
        .parse()
        .unwrap();
        Ok(Postgres { container, url })
    }
}

pub struct GraphNode {
    pub container: ContainerAsync<GenericImage>,
}

impl GraphNode {
    pub async fn new(name: &str, postgres: &Url, ipfs: &Url, rpc: &Url) -> anyhow::Result<Self> {
        let ipfs_port = ipfs.port().unwrap();
        let container = GenericImage::new("graphprotocol/graph-node", "v0.35.1")
            // .with_wait_for(WaitFor::Log(LogWaitStrategy::))
            .with_exposed_port(ContainerPort::Tcp(8080))
            .with_exposed_port(ContainerPort::Tcp(ipfs_port))
            .with_container_name(name)
            .with_env_var("POSTGRES_URL", postgres.to_string())
            .with_env_var("IPFS", ipfs.to_string())
            .with_env_var("ETHEREUM_RPC", format!("local:{}", rpc))
            .with_cmd(["sh", "-c", "unset GRAPH_NODE_CONFIG; graph-node"])
            .start()
            .await?;
        Ok(GraphNode { container })
    }
}
