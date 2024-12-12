use starknet::{ContractAddress};

#[starknet::interface]
pub trait InterlinkTrait<TContractState> {
    fn initialize(ref self: TContractState);
    fn whitelist_account(ref self: TContractState, account: ContractAddress);
    fn blacklist_account(ref self: TContractState, account: ContractAddress);
    fn deposit(ref self: TContractState, token: ContractAddress, amount: u256);
    fn withdraw(
        ref self: TContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
    );
    fn swap(
        ref self: TContractState,
        token1: ContractAddress,
        token2: ContractAddress,
        amount_token1: u256
    );
    fn transfer(
        ref self: TContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
    );
    fn pause_vault(ref self: TContractState);
    fn reactivate_vault(ref self: TContractState);
    fn get_user_balance(self: @TContractState, account: ContractAddress) -> u256;
    fn get_linked_accounts(
        self: @TContractState, account: ContractAddress
    ) -> Array<ContractAddress>;
    fn get_total_users(self: @TContractState) -> u64;
    fn get_total_deposits(self: @TContractState) -> u256;
    fn get_total_withdrawals(self: @TContractState) -> u256;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn get_user_vault_balance(
        self: @TContractState, user: ContractAddress, token: ContractAddress
    ) -> (ContractAddress, u256);
    fn check_account_is_whitelisted(self: @TContractState, account: ContractAddress) -> bool;
    fn update_vault_classhash(ref self: TContractState, new_classhash: starknet::ClassHash);
}

#[starknet::interface]
pub trait IMainVaultTrait<TContractState> {
    fn get_vault_balance(
        self: @TContractState, vault: ContractAddress, token: ContractAddress
    ) -> (ContractAddress, u256);
    fn withdraw(
        ref self: TContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
    );
    fn swap(
        ref self: TContractState,
        token1: ContractAddress,
        token2: ContractAddress,
        amount_token1: u256
    );
    fn transfer(
        ref self: TContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
    );
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}
