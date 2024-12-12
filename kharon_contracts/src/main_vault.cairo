#[starknet::contract]
pub mod Vault {
    use starknet::{ContractAddress, get_contract_address};
    use openzeppelin::{
        access::ownable::OwnableComponent,
        token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait}
    };
    use crate::interfaces::IMainVaultTrait;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        interlink: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, interlink_contract: ContractAddress) {
        self.ownable.initializer(interlink_contract);
        self.interlink.write(interlink_contract);
    }

    #[abi(embed_v0)]
    impl IMainVaultImpl of IMainVaultTrait<ContractState> {
        fn get_vault_balance(
            self: @ContractState, vault: ContractAddress, token: ContractAddress
        ) -> (ContractAddress, u256) {
            self.ownable.assert_only_owner();
            let vault_balance = IERC20Dispatcher { contract_address: token }.balance_of(vault);
            (token, vault_balance)
        }

        fn withdraw(
            ref self: ContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
        ) {
            self.ownable.assert_only_owner();
            IERC20Dispatcher { contract_address: token }.transfer(receiver, amount);
        }

        fn swap(
            ref self: ContractState,
            token1: ContractAddress,
            token2: ContractAddress,
            amount_token1: u256
        ) {
            self.ownable.assert_only_owner();
            ///TODO implement swap
        }
        fn transfer(
            ref self: ContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
        ) {
            self.ownable.assert_only_owner();
            IERC20Dispatcher { contract_address: token }.transfer(receiver, amount);
        }
    }
}
