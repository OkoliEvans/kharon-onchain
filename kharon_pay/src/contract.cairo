#[starknet::contract]
pub mod KharonPay {
    use OwnableComponent::InternalTrait;
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::upgrades::{ UpgradeableComponent, interface::IUpgradeable };
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address, ClassHash,
    };
    use crate::interfaces::IKharonPay;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        is_token_supported: Map<ContractAddress, bool>,
        is_system_paused: bool,
        supported_tokens: Vec<ContractAddress>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TokenAdded: TokenAdded,
        TokenRemoved: TokenRemoved,
        PaymentReceived: PaymentReceived,
        SystemPaused: SystemPaused,
        SystemUnpaused: SystemUnpaused,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenAdded {
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenRemoved {
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct PaymentReceived {
        sender: ContractAddress,
        token: ContractAddress,
        amount: u256,
        reference: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    struct SystemPaused {
        pause_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct SystemUnpaused {
        unpause_time: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl IKharonPayImpl of IKharonPay<ContractState> {
        fn receive_payment(
            ref self: ContractState, token: ContractAddress, amount: u256, reference: ByteArray,
        ) {
            assert!(reference.len() > 0, "Reference cannot be empty");
            assert!(token.is_non_zero(), "Token address cannot be zero");
            assert!(amount > 0, "Amount must be greater than zero");
            assert!(self.is_supported_token(token), "Token is not supported");
            assert!(!self.get_system_status(), "System is paused");

            let caller = get_caller_address();
            let token_dispatcher = ERC20ABIDispatcher { contract_address: token };
            token_dispatcher.transfer_from(caller, get_contract_address(), amount);

            self.emit(PaymentReceived { sender: caller, token, amount, reference });
        }


        fn add_supported_token(ref self: ContractState, token: ContractAddress) {
            self.ownable.assert_only_owner();
            assert!(!self.get_system_status(), "System is paused");
            assert!(token.is_non_zero(), "Token address cannot be zero");
            assert!(!self.is_supported_token(token), "Token is already supported");

            self.is_token_supported.entry(token).write(true);
            self.supported_tokens.push(token);
            self.emit(TokenAdded { token });
        }

        fn remove_supported_token(ref self: ContractState, token: ContractAddress) {
            self.ownable.assert_only_owner();
            assert!(!self.get_system_status(), "System is paused");
            assert!(self.is_supported_token(token), "Token is not supported");

            let len = self.supported_tokens.len();
            let mut index = 0;

            while index != len {
                if self.supported_tokens.at(index).read() == token {
                    let last_element = self.supported_tokens.at(len - 1).read();
                    self.supported_tokens.at(index).write(last_element);
                    let _ = self.supported_tokens.pop();
                    break;
                }
                index += 1;
            }
            self.is_token_supported.entry(token).write(false);
            self.emit(TokenRemoved { token });
        }

        fn is_supported_token(ref self: ContractState, token: ContractAddress) -> bool {
            self.is_token_supported.entry(token).read()
        }

        fn pause_system(ref self: ContractState) {
            self.ownable.assert_only_owner();
            assert!(!self.get_system_status(), "System is already paused");

            self.is_system_paused.write(true);
            self.emit(SystemPaused { pause_time: get_block_timestamp() });
        }


        fn unpause_system(ref self: ContractState) {
            self.ownable.assert_only_owner();
            assert!(self.get_system_status(), "System is already unpaused");

            self.is_system_paused.write(false);
            self.emit(SystemUnpaused { unpause_time: get_block_timestamp() });
        }

        fn get_system_status(self: @ContractState) -> bool {
            self.is_system_paused.read()
        }

        fn get_supported_tokens(self: @ContractState) -> Array<ContractAddress> {
            let mut local_supported_tokens = self.supported_tokens.clone();
            let mut arr = ArrayTrait::new();
            let mut index = 0;
            let len = local_supported_tokens.len();

            while index != len {
                let token = local_supported_tokens.at(index).read();
                arr = array_append(arr, token);
                index += 1;
            }

            arr
        }

        fn withdraw(ref self: ContractState, token: ContractAddress, receiver: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            assert!(receiver.is_non_zero(), "Receiver address cannot be zero");
            assert!(amount > 0, "Amount must be greater than zero");
            assert!(self.is_supported_token(token), "Token is not supported");
            assert!(!self.get_system_status(), "System is paused");

            let token_dispatcher = ERC20ABIDispatcher { contract_address: token };
            token_dispatcher.transfer(receiver, amount);
        }
    }
    
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    fn array_append<T>(mut arr: Array<T>, value: T) -> Array<T> {
        arr.append(value);
        arr
    }

}
