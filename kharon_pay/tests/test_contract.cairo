use starknet::{ContractAddress, contract_address_const};

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};
use kharon_pay::{ contract::KharonPay, mock_erc20::ERC20, interfaces::{IKharonPayDispatcher, IKharonPayDispatcherTrait} };
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

fn deploy_contract() -> ContractAddress {
    let contract = declare("KharonPay").unwrap().contract_class();
    
    let mut calldata = ArrayTrait::new();
    let owner: ContractAddress = contract_address_const::<'owner'>();

    owner.serialize(ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
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
fn test_add_supported_token() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_add_supported_token_should_panic_unauthorized_caller() {
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };

    dispatcher.add_supported_token(token_address);
}

#[test]
fn test_receive_payment() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(token_address, recipient);
    erc20_dispatcher.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(contract_address, recipient);
    dispatcher.receive_payment(token_address, 1000, "test");
    stop_cheat_caller_address(contract_address);

    let balance = erc20_dispatcher.balance_of(contract_address);
    assert_eq!(balance, 1000, "Balance should be 1000");
}


#[test]
#[should_panic(expected: "Reference cannot be empty")]
fn test_receive_payment_should_panic_no_reference() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(token_address, recipient);
    erc20_dispatcher.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(contract_address, recipient);
    dispatcher.receive_payment(token_address, 1000, "");
    stop_cheat_caller_address(contract_address);

    let balance = erc20_dispatcher.balance_of(contract_address);
    assert_eq!(balance, 1000, "Balance should be 1000");
}

#[test]
fn test_remove_supported_token() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, owner);
    dispatcher.remove_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    let is_supported = dispatcher.is_supported_token(token_address);
    assert_eq!(is_supported, false, "Token should not be supported");
}

#[test]
fn test_pause_system() {
    let owner: ContractAddress = contract_address_const::<'owner'>();

    let contract_address = deploy_contract();
    let dispatcher = IKharonPayDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.pause_system();
    stop_cheat_caller_address(contract_address);

    let is_paused = dispatcher.get_system_status();
    assert_eq!(is_paused, true, "System should be paused");
}

#[test]
#[should_panic(expected: "System is paused")]
fn test_receive_payment_should_panic_system_paused() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(token_address, recipient);
    erc20_dispatcher.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(contract_address, owner);
    dispatcher.pause_system();
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, recipient);
    dispatcher.receive_payment(token_address, 1000, "test");
    stop_cheat_caller_address(contract_address);

    let balance = erc20_dispatcher.balance_of(contract_address);
    assert_eq!(balance, 1000, "Balance should be 1000");
}


#[test]
#[should_panic(expected: "System is paused")]
fn test_add_supported_token_should_panic_system_paused() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.pause_system();
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_withdraw() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(token_address, recipient);
    erc20_dispatcher.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(contract_address, recipient);
    dispatcher.receive_payment(token_address, 1000, "test");
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, owner);
    dispatcher.withdraw(token_address, recipient, 500);
    stop_cheat_caller_address(contract_address);

    let balance = erc20_dispatcher.balance_of(contract_address);
    assert_eq!(balance, 500, "Owner should have withdrawn 500");
}

#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_withdraw_should_panic_unauthorized_caller() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(token_address, recipient);
    erc20_dispatcher.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(contract_address, recipient);
    dispatcher.receive_payment(token_address, 1000, "test");
    stop_cheat_caller_address(contract_address);

    dispatcher.withdraw(token_address, recipient, 500);

    let balance = erc20_dispatcher.balance_of(contract_address);
    assert_eq!(balance, 500, "Owner should have withdrawn 500");
}

#[test]
#[should_panic(expected: "System is paused")]
fn test_withdraw_should_panic_system_paused() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address: token_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(token_address, recipient);
    erc20_dispatcher.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(contract_address, recipient);
    dispatcher.receive_payment(token_address, 1000, "test");
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, owner);
    dispatcher.pause_system();
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, owner);
    dispatcher.withdraw(token_address, recipient, 500);
    stop_cheat_caller_address(contract_address);

    let balance = erc20_dispatcher.balance_of(contract_address);
    assert_eq!(balance, 500, "Owner should have withdrawn 500");
}

#[test]
fn test_get_supported_tokens() {
    let owner: ContractAddress = contract_address_const::<'owner'>();
    let recipient: ContractAddress = contract_address_const::<'recipient'>();

    let contract_address = deploy_contract();
    let token_address = deploy_token(recipient);

    let dispatcher = IKharonPayDispatcher { contract_address };

    start_cheat_caller_address(contract_address, owner);
    dispatcher.add_supported_token(token_address);
    stop_cheat_caller_address(contract_address);

    let supported_tokens = dispatcher.get_supported_tokens();
    assert_eq!(supported_tokens.len(), 1, "There should be one supported token");
}