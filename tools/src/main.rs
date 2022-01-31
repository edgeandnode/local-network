use clap::{arg, App, AppSettings, Arg, ArgMatches};
use primitive_types::U256;
use secp256k1::{Secp256k1, SecretKey};
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
        .subcommand(
            App::new("sign")
                .about("sign message")
                .arg(arg!(<message>))
                .arg(arg!(<private_key>)),
        )
        .get_matches();
    let verbose = args.is_present("verbose");
    match args.subcommand() {
        Some(("message", args)) => message(args, verbose),
        Some(("sign", args)) => sign(args, verbose),
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

fn sign(args: &ArgMatches, verbose: bool) {
    let message = match from_hex(args.value_of("message").unwrap())
        .and_then(|msg| secp256k1::Message::from_slice(&msg).map_err(Into::into))
    {
        Ok(message) => message,
        Err(err) => {
            println!("message: {}", err);
            return;
        }
    };
    let private_key = match from_hex(args.value_of("private_key").unwrap())
        .and_then(|key| SecretKey::from_slice(&key).map_err(Into::into))
    {
        Ok(private_key) => private_key,
        Err(err) => {
            println!("private_key: {}", err);
            return;
        }
    };
    let signature = Secp256k1::new().sign_recoverable(&message, &private_key);
    let (recovery_id, signature) = signature.serialize_compact();
    let recovery_id = match recovery_id.to_i32() {
        0 | 27 => 27,
        1 | 28 => 28,
        recovery_id => panic!("Invalid recovery id: {}", recovery_id),
    };
    if verbose {
        println!("recovery_id: {}", recovery_id);
    }
    let mut serialized = [0; 65];
    (&mut serialized[..64]).copy_from_slice(&signature);
    serialized[64] = recovery_id;
    println!("{}", to_hex(&serialized));
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

fn from_hex(input: &str) -> Result<Vec<u8>, Box<dyn Error>> {
    let input = input
        .strip_prefix("0x")
        .ok_or_else(|| "expected 0x prefix".to_string())?;
    hex::decode(input).map_err(Into::into)
}

fn to_hex(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}
