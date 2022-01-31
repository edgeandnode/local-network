use clap::{App, AppSettings, Arg, ArgMatches};
use primitive_types::U256;
use sha3::{Digest as _, Keccak256};
use std::error::Error;

fn main() {
    let args = App::new(env!("CARGO_CRATE_NAME"))
        .setting(AppSettings::ArgRequiredElseHelp)
        .arg(
            Arg::new("verbose")
                .short('v')
                .long("verbose")
                .help("Show verbose output"),
        )
        .subcommand(
            App::new("message")
                .about("construct message")
                .arg(Arg::new("args").required(true).min_values(1)),
        )
        .get_matches();
    let verbose = args.is_present("verbose");
    match args.subcommand() {
        Some(("message", args)) => message(args, verbose),
        _ => panic!("unexpected subcommand"),
    };
}

fn message(args: &ArgMatches, verbose: bool) {
    let mut hasher = Keccak256::default();
    for (i, arg) in args.values_of("args").unwrap().enumerate() {
        match parse_arg(arg) {
            Ok(bytes) => {
                if verbose {
                    println!("{:2}: {}", i, to_hex(&bytes));
                }
                hasher.update(&bytes);
            }
            Err(err) => {
                println!("{}", err);
                return;
            }
        };
    }
    let message: [u8; 32] = hasher.finalize().into();
    println!("{}", to_hex(&message));
}

fn parse_arg(arg: &str) -> Result<Vec<u8>, Box<dyn Error>> {
    if arg.starts_with("0x") {
        hex::decode(arg.strip_prefix("0x").unwrap()).map_err(Into::into)
    } else if let Some(value) = arg.parse::<f64>().ok() {
        let mut bytes = [0u8; 32];
        U256::from_dec_str(&(value * 1e18).to_string())?.to_big_endian(&mut bytes);
        Ok(bytes.to_vec())
    } else {
        Err(format!("unable to parse argument: `{}`", arg).into())
    }
}

fn to_hex(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}
