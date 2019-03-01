#!/usr/bin/env python3
import solc


# decrypt keystore file and return account
def account_from_key(w3, key_path, passphrase):
    with open(key_path) as key_file:
        key_json = key_file.read()
    private_key = w3.eth.account.decrypt(key_json, passphrase)
    account = w3.eth.account.privateKeyToAccount(private_key)
    return account


# compile contract using solc and return contract interface
def compile_contract(path, name):
    compiled_contacts = solc.compile_files([path])
    contract_interface = compiled_contacts['{}:{}'.format(path, name)]
    return contract_interface


# compile contract, deploy it from account specified, then return transaction hash and contract interface
def deploy_contract(w3, account, path, name):
    contract_interface = compile_contract(path, name)
    contract = w3.eth.contract(abi=contract_interface['abi'], bytecode=contract_interface['bin'])
    transaction = contract.constructor().buildTransaction({
        'nonce': w3.eth.getTransactionCount(account.address),
        'from': account.address
    })
    signed_transaction = w3.eth.account.signTransaction(transaction, account.privateKey)
    tx_hash = w3.eth.sendRawTransaction(signed_transaction.rawTransaction)
    return tx_hash.hex(), contract_interface


# return address of fresh created contract using hash returned from deploy_contract
# return None if transaction was not included to block
def created_contract_address(w3, tx_hash):
    tx_receipt = w3.eth.getTransactionReceipt(tx_hash)
    if not tx_receipt:
        return None
    return tx_receipt['contractAddress']


# wait for deploy transaction to be included to block, return address of created contract
def wait_contract_address(w3, tx_hash):
    w3.eth.waitForTransactionReceipt(tx_hash)
    return created_contract_address(w3, tx_hash)


# return contract object using its address and ABI
def get_contract(w3, address, abi):
    return w3.eth.contract(address=address, abi=abi)


# make transaction to contract invoking function, return transaction hash
def transact_function(w3, account, contract, function_name, args=None):
    if args:
        transactor = contract.functions[function_name](args)
    else:
        transactor = contract.functions[function_name]()

    transaction = transactor.buildTransaction({
        'nonce': w3.eth.getTransactionCount(account.address),
        'from': account.address
    })
    signed_transaction = w3.eth.account.signTransaction(transaction, account.privateKey)
    tx_hash = w3.eth.sendRawTransaction(signed_transaction.rawTransaction)
    return tx_hash.hex()


# make call to contract function, return the result of call
def call_function(account, contract, function_name, args=None):
    if args:
        caller = contract.functions[function_name](args)
    else:
        caller = contract.functions[function_name]()
    return caller.call({'from': account.address})


# return event data from transaction with hash tx_hash
# return None if transaction was not included to block
def get_event(w3, contract, tx_hash, event_name):
    tx_receipt = w3.eth.getTransactionReceipt(tx_hash)
    if not tx_receipt:
        return None
    return contract.events[event_name]().processReceipt(tx_receipt)


# wait for transaction to be included to block, return event data
def wait_event(w3, contract, tx_hash, event_name):
    w3.eth.waitForTransactionReceipt(tx_hash)
    return get_event(w3, contract, tx_hash, event_name)
