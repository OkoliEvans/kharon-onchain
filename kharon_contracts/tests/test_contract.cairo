use starknet::{ContractAddress};

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};
use kharon_contracts::{inter_link::InterLink, main_vault::Vault, mock_erc20::ERC20};
use kharon_contracts::interfaces::{
    InterlinkTrait, InterlinkTraitDispatcher, InterlinkTraitDispatcherTrait,
    IMainVaultTraitDispatcher, IMainVaultTraitDispatcherTrait, IERC20DispatcherTrait,
    IERC20Dispatcher,
};

use core::num::traits::Zero;


fn deploy_interlink_contract(name: ByteArray) -> ContractAddress {
    let main_vault_class = declare("Vault").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    let owner: ContractAddress = starknet::contract_address_const::<1234>();

    owner.serialize(ref constructor_calldata);
    main_vault_class.serialize(ref constructor_calldata);

    let contract_class = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract_class.deploy(@constructor_calldata).unwrap();

    contract_address
}

fn deploy_token(recipient: ContractAddress) -> ContractAddress {
    let mut constructor_calldata = ArrayTrait::new();
    recipient.serialize(ref constructor_calldata);

    let contract_class = declare("ERC20").unwrap().contract_class();
    let (token_address, _) = contract_class.deploy(@constructor_calldata).unwrap();
    token_address
}

#[test]
fn test_initialize() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let contract_address = deploy_interlink_contract("InterLink");

    let dispatcher = InterlinkTraitDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.initialize();

    let stored_owner = dispatcher.get_owner();
    assert(stored_owner == owner, 'Not owner');
}

#[test]
fn test_whitelist_account() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();
    let contract_address = deploy_interlink_contract("InterLink");

    let dispatcher = InterlinkTraitDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(account);

    let whitelisted_account = dispatcher.check_account_is_whitelisted(account);
    stop_cheat_caller_address(contract_address);

    assert(whitelisted_account == true, 'not the whitelisted account');
}

#[test]
fn test_blacklist_account() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();
    let contract_address = deploy_interlink_contract("InterLink");

    let dispatcher = InterlinkTraitDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(account);
    dispatcher.blacklist_account(account);
    let whitelisted_account = dispatcher.check_account_is_whitelisted(account);
    stop_cheat_caller_address(contract_address);

    assert(whitelisted_account == false, 'not the whitelisted account');
}

#[test]
fn test_deposit() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();

    let token = deploy_token(owner);
    assert(token.is_non_zero(), 'token is zero');

    let contract_addr = deploy_interlink_contract("InterLink");
    assert(contract_addr.is_non_zero(), 'interlink address is zero addr');

    let token_dispatcher = IERC20Dispatcher { contract_address: token };
    assert(token_dispatcher.balance_of(owner) == 1000, 'inaccurate owner balance');

    let dispatcher = InterlinkTraitDispatcher { contract_address: contract_addr };

    start_cheat_caller_address(token, owner);
    token_dispatcher.approve(contract_addr, 200);
    stop_cheat_caller_address(token);

    start_cheat_caller_address(contract_addr, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(owner);
    dispatcher.deposit(token, 100);
    let (_, vault_balance) = dispatcher.get_user_vault_balance(owner, token);
    let owner_balance = dispatcher.get_user_balance(owner);
    let total_deposit = dispatcher.get_total_deposits();
    assert(vault_balance == 100 && owner_balance == 100, 'inaccurate balance');
    assert(total_deposit == 100, 'incorrect deposit');
    stop_cheat_caller_address(contract_addr);
}


#[test]
fn test_withdraw() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();

    let token = deploy_token(owner);
    assert(token.is_non_zero(), 'token is zero');

    let contract_addr = deploy_interlink_contract("InterLink");
    assert(contract_addr.is_non_zero(), 'interlink address is zero addr');

    let token_dispatcher = IERC20Dispatcher { contract_address: token };
    assert(token_dispatcher.balance_of(owner) == 1000, 'inaccurate owner balance');

    let dispatcher = InterlinkTraitDispatcher { contract_address: contract_addr };

    start_cheat_caller_address(token, owner);
    token_dispatcher.approve(contract_addr, 200);
    stop_cheat_caller_address(token);

    start_cheat_caller_address(contract_addr, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(owner);
    dispatcher.deposit(token, 100);
    dispatcher.withdraw(token, owner, 20);
    assert(dispatcher.get_user_vault_balance(owner, token) == 80, 'incorrect vault balance');
    assert(dispatcher.get_user_balance(owner) == 80, 'inaccurate user balance');
    stop_cheat_caller_address(contract_addr);
}

#[test]
fn test_transfer() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let owner2: ContractAddress = starknet::contract_address_const::<123456>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();

    let token = deploy_token(owner);
    assert(token.is_non_zero(), 'token is zero');

    let contract_addr = deploy_interlink_contract("InterLink");
    assert(contract_addr.is_non_zero(), 'interlink address is zero addr');

    let token_dispatcher = IERC20Dispatcher { contract_address: token };
    assert(token_dispatcher.balance_of(owner) == 1000, 'inaccurate owner balance');

    let dispatcher = InterlinkTraitDispatcher { contract_address: contract_addr };

    start_cheat_caller_address(token, owner);
    token_dispatcher.approve(contract_addr, 500);
    stop_cheat_caller_address(token);

    start_cheat_caller_address(contract_addr, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(owner);
    dispatcher.deposit(token, 400);
    dispatcher.transfer(token, owner2, 200);
    assert(dispatcher.get_user_vault_balance(owner, token) == 200, 'incorrect vault balance');
    assert(token_dispatcher.balance_of(owner2) == 200, 'inaccurate user balance');
    stop_cheat_caller_address(contract_addr);
}

#[test]
#[should_panic(expected: "transfer: not whitelisted or vault paused")]
fn test_pause_vault() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let owner2: ContractAddress = starknet::contract_address_const::<123456>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();

    let token = deploy_token(owner);
    assert(token.is_non_zero(), 'token is zero');

    let contract_addr = deploy_interlink_contract("InterLink");
    assert(contract_addr.is_non_zero(), 'interlink address is zero addr');

    let token_dispatcher = IERC20Dispatcher { contract_address: token };
    assert(token_dispatcher.balance_of(owner) == 1000, 'inaccurate owner balance');

    let dispatcher = InterlinkTraitDispatcher { contract_address: contract_addr };

    start_cheat_caller_address(token, owner);
    token_dispatcher.approve(contract_addr, 500);
    stop_cheat_caller_address(token);

    start_cheat_caller_address(contract_addr, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(owner);
    dispatcher.deposit(token, 400);
    dispatcher.pause_vault();
    dispatcher.transfer(token, owner2, 200);
    stop_cheat_caller_address(contract_addr);
}

#[test]
fn test_reactivate_vault() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let owner2: ContractAddress = starknet::contract_address_const::<123456>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();

    let token = deploy_token(owner);
    assert(token.is_non_zero(), 'token is zero');

    let contract_addr = deploy_interlink_contract("InterLink");
    assert(contract_addr.is_non_zero(), 'interlink address is zero addr');

    let token_dispatcher = IERC20Dispatcher { contract_address: token };
    assert(token_dispatcher.balance_of(owner) == 1000, 'inaccurate owner balance');

    let dispatcher = InterlinkTraitDispatcher { contract_address: contract_addr };

    start_cheat_caller_address(token, owner);
    token_dispatcher.approve(contract_addr, 500);
    println!("allowance of owner {}", token_dispatcher.allowance(owner, contract_addr));
    stop_cheat_caller_address(token);

    start_cheat_caller_address(contract_addr, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(owner);
    dispatcher.deposit(token, 400);
    dispatcher.pause_vault();
    dispatcher.reactivate_vault();
    dispatcher.transfer(token, owner2, 200);
    stop_cheat_caller_address(contract_addr);
}

#[test]
#[should_panic(expected: "transfer: not whitelisted or vault paused")]
fn test_not_whitelisted() {
    let owner: ContractAddress = starknet::contract_address_const::<1234>();
    let owner2: ContractAddress = starknet::contract_address_const::<123456>();
    let account: ContractAddress = starknet::contract_address_const::<0x0233335566>();

    let token = deploy_token(owner);
    assert(token.is_non_zero(), 'token is zero');

    let contract_addr = deploy_interlink_contract("InterLink");
    assert(contract_addr.is_non_zero(), 'interlink address is zero addr');

    let token_dispatcher = IERC20Dispatcher { contract_address: token };
    assert(token_dispatcher.balance_of(owner) == 1000, 'inaccurate owner balance');

    let dispatcher = InterlinkTraitDispatcher { contract_address: contract_addr };

    start_cheat_caller_address(token, owner);
    token_dispatcher.approve(contract_addr, 500);
    stop_cheat_caller_address(token);

    start_cheat_caller_address(contract_addr, owner);
    dispatcher.initialize();
    dispatcher.whitelist_account(owner);
    dispatcher.deposit(token, 400);
    stop_cheat_caller_address(contract_addr);

    start_cheat_caller_address(contract_addr, owner2);
    dispatcher.transfer(token, owner2, 200);
    stop_cheat_caller_address(contract_addr);
}

