import json
import os
import sys
import time
from dotenv import load_dotenv
from eip712.messages import EIP712Message
from eth_account.messages import encode_defunct
from web3 import Web3
from web3.exceptions import ContractLogicError, ContractCustomError
from eth_utils.abi import collapse_if_tuple, function_abi_to_4byte_selector

def decode_custom_error(contract_abi, error_data, w3):
    for error in [abi for abi in contract_abi if abi["type"] == "error"]:
        name = error["name"]
        data_types = [
            collapse_if_tuple(abi_input) for abi_input in error.get("inputs", [])
        ]
        error_signature_hex = function_abi_to_4byte_selector(error).hex()
        if error_signature_hex.casefold() == str(error_data)[2:10].casefold():
            params = ",".join(
                [
                    str(x)
                    for x in w3.codec.decode(
                        data_types, bytes.fromhex(str(error_data)[10:])
                    )
                ]
            )
            decoded = f"{name} ({str(params)})"
            return decoded
    return None


load_dotenv()
ESCROW_ADDRESS = sys.argv[1]
DOCKER_GATEWAY_HOST = os.getenv('CHAIN_HOST')
CHAIN_RPC = os.getenv('CHAIN_RPC')
GATEWAY_SENDER_ADDRESS = os.getenv('GATEWAY_SENDER_ADDRESS')
GATEWAY_SIGNER_ADDRESS = os.getenv('GATEWAY_SIGNER_ADDRESS')
GATEWAY_SIGNER_SECRET_KEY = os.getenv('GATEWAY_SIGNER_SECRET_KEY')


w3 = Web3(Web3.HTTPProvider(f"http://{DOCKER_GATEWAY_HOST}:{CHAIN_RPC}"))

timer = int(time.time()) + 86400
# Authorization
hashed_data = Web3.solidity_keccak(
    ["uint256", "uint256", "address"], [1337, timer, GATEWAY_SENDER_ADDRESS]
)
encode_data = encode_defunct(hashed_data)
signature_authorization = w3.eth.account.sign_message(
    encode_data, private_key=GATEWAY_SIGNER_SECRET_KEY
)
# Load abi to make calls to the Escrow contract
escrow_abi_json = json.load(open("Escrow.abi.json"))
escrow = w3.eth.contract(address=ESCROW_ADDRESS, abi=escrow_abi_json)


# ESCROW CONTRACT CALLS
try:
    print("--- Approving signer")

    escrow.functions.authorizeSigner(
        GATEWAY_SIGNER_ADDRESS, timer, signature_authorization.signature
    ).transact({"from": GATEWAY_SENDER_ADDRESS})
   
    print("Signer Approved")
except ContractCustomError as e:
    raise ContractCustomError(decode_custom_error(escrow_abi_json, str(e), w3))
except ContractLogicError as e:
    raise ContractLogicError(f"Logic Error: {e}")
