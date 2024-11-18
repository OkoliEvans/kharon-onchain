#[starknet::contract]
pub mod InterLink {
    use starknet::event::EventEmitter;
    use crate::interfaces::{
        InterlinkTrait, IMainVaultTraitDispatcher, IMainVaultTraitDispatcherTrait, IERC20Dispatcher,
        IERC20DispatcherTrait
    };
    use starknet::{
        ContractAddress, contract_address, get_caller_address, get_contract_address,
        get_block_timestamp, ClassHash,
        storage::{
            StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry,
            StorageMapReadAccess, StorageMapWriteAccess, Map, Vec, MutableVecTrait, VecTrait
        },
        syscalls::deploy_syscall,
    };
    use openzeppelin::{access::ownable::OwnableComponent};
    use core::num::traits::Zero;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        total_deposits: u256,
        total_withdrawals: u256,
        total_users_vaults: u256,
        vault_classhash: ClassHash,
        users: Vec<ContractAddress>,
        user_initialized: Map::<ContractAddress, bool>,
        user_vault: Map::<ContractAddress, ContractAddress>,
        is_whitelisted: Map::<ContractAddress, Map<ContractAddress, bool>>,
        user_vault_deployed: Map::<ContractAddress, Map<ContractAddress, bool>>,
        is_user_vault_paused: Map::<ContractAddress, Map<ContractAddress, bool>>,
        user_vault_balance: Map::<ContractAddress, Map<ContractAddress, u256>>,
        user_whitelisted_accounts: Map::<ContractAddress, Vec<ContractAddress>>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccountWhitelisted: AccountWhitelisted,
        AccountBlacklisted: AccountBlacklisted,
        VaultPaused: VaultPaused,
        VaultReactivated: VaultReactivated,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct AccountWhitelisted {
        user: ContractAddress,
        account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct AccountBlacklisted {
        user: ContractAddress,
        account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct VaultPaused {
        user: ContractAddress,
        paused_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct VaultReactivated {
        user: ContractAddress,
        reactivated_at: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, vault_classhash: ClassHash) {
        self.ownable.initializer(owner);
        self.vault_classhash.write(vault_classhash);
    }

    #[abi(embed_v0)]
    impl InterlinkImpl of InterlinkTrait<ContractState> {
        fn initialize(ref self: ContractState) {
            let caller = get_caller_address();
            self.users.append().write(caller);
            self.user_initialized.entry(caller).write(true);
        }

        fn whitelist_account(ref self: ContractState, account: ContractAddress) {
            let caller = get_caller_address();
            let is_whitelisted = self.is_whitelisted.entry(caller).entry(account);
            let user_whitelisted_accounts = self.user_whitelisted_accounts.entry(caller);

            assert!(account.is_non_zero(), "whitelist account: Zero address");
            assert!(is_whitelisted.read() == false, "whitelist account: account whitelisted");
            assert!(
                self.user_initialized.entry(caller).read() == true,
                "whitelist: caller not initialized"
            );

            is_whitelisted.write(true);
            user_whitelisted_accounts.append().write(account);

            assert!(is_whitelisted.read() == true, "whitelist not successful");

            self.emit(AccountWhitelisted { user: caller, account });
        }

        fn blacklist_account(ref self: ContractState, account: ContractAddress) {
            let caller = get_caller_address();
            assert!(account.is_non_zero(), "whitelist account: Zero address");
            assert!(
                self.is_whitelisted.entry(caller).entry(account).read() == true,
                "blacklist account: account not whitelisted"
            );

            let user_accts_vec = self.user_whitelisted_accounts.entry(caller);
            let mut i = 0;

            while i <= user_accts_vec.len() {
                if user_accts_vec.at(i).read() == account {
                    self.is_whitelisted.entry(caller).entry(account).write(false);
                    break;
                }
                i += 1;
            };

            self.emit(AccountBlacklisted { user: caller, account });
        }

        fn deposit(ref self: ContractState, token: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            let contract = get_contract_address();
            let vault_classhash = self.vault_classhash.read();
            let vault_deployed = self.user_vault_deployed.entry(caller);
            let user_vault_balance = self.user_vault_balance.entry(caller);

            let mut user_vault: ContractAddress = self.user_vault.entry(caller).read();
            let mut user_vault_deployed = self
                .user_vault_deployed
                .entry(caller)
                .entry(user_vault)
                .read();

            let is_vault_paused: bool = self.check_vault_is_paused();

            assert!(token.is_non_zero(), "deposit: token zero address");
            assert!(amount > 0, "deposit: invalid amount");
            assert!(is_vault_paused == false, "deposit: vault paused");

            let mut payload = array![];
            contract.serialize(ref payload);

            if !user_vault_deployed {
                let (user_vault_contract, _) = deploy_syscall(
                    vault_classhash, 0, payload.span(), false
                )
                    .unwrap();
                user_vault = user_vault_contract;
                self.user_vault.entry(caller).write(user_vault_contract);
                self.total_users_vaults.write(self.total_users_vaults.read() + 1);

                vault_deployed.entry(user_vault).write(true);

                assert!(
                    user_vault_contract.is_non_zero()
                        && vault_deployed.entry(user_vault).read() == true,
                    "user vault not deployed"
                );
            }

            IERC20Dispatcher { contract_address: token }.transfer_from(caller, user_vault, amount);

            self.total_deposits.write(self.total_deposits.read() + amount);
            user_vault_balance
                .entry(user_vault)
                .write(user_vault_balance.entry(user_vault).read() + amount);
        }

        fn withdraw(
            ref self: ContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
        ) {
            let caller = get_caller_address();
            let user_vault = self.user_vault.entry(caller).read();
            let (_, balance) = self.get_user_vault_balance(caller, token);
            let is_whitelisted = self.check_is_whitelisted(caller);
            let is_vault_paused: bool = self.check_vault_is_paused();
            let user_vault_balance = self.user_vault_balance.entry(caller).entry(user_vault);

            assert!(token.is_non_zero(), "withdraw: token zero address");
            assert!(receiver.is_non_zero(), "withdraw: receiver zero address");
            assert!(amount > 0, "withdraw: invalid amount");
            assert!(balance >= amount, "withdraw: insufficient balance");
            assert!(
                is_whitelisted && !is_vault_paused, "withdraw: not whitelisted or vault paused"
            );

            IMainVaultTraitDispatcher { contract_address: user_vault }
                .withdraw(token, receiver, amount);
            user_vault_balance.write(user_vault_balance.read() - amount);
            self.total_withdrawals.write(self.total_withdrawals.read() + amount);
        }

        ///@notice swap not implemented in the main vault yet, do not interact
        fn swap(
            ref self: ContractState,
            token1: ContractAddress,
            token2: ContractAddress,
            amount_token1: u256
        ) {
            let caller = get_caller_address();
            let is_whitelisted = self.check_is_whitelisted(caller);
            let is_vault_paused: bool = self.check_vault_is_paused();

            assert!(token1.is_non_zero(), "swap: token1 zero address");
            assert!(token2.is_non_zero(), "swap: token2 zero address");
            assert!(amount_token1 > 0, "swap: invalid token1 amount");
            assert!(is_whitelisted && !is_vault_paused, "swap: not whitelisted or vault paused");

            IMainVaultTraitDispatcher { contract_address: self.user_vault.entry(caller).read() }
                .swap(token1, token2, amount_token1);
        }


        fn transfer(
            ref self: ContractState, token: ContractAddress, receiver: ContractAddress, amount: u256
        ) {
            let caller = get_caller_address();
            let is_whitelisted = self.check_is_whitelisted(caller);
            let is_vault_paused: bool = self.check_vault_is_paused();
            let user_vault = self.user_vault.entry(caller).read();
            let user_vault_balance = self.user_vault_balance.entry(caller).entry(user_vault);

            assert!(receiver.is_non_zero(), "transfer: token1 zero address");
            assert!(amount > 0, "transfer: invalid amount");
            assert!(
                is_whitelisted && !is_vault_paused, "transfer: not whitelisted or vault paused"
            );

            IMainVaultTraitDispatcher { contract_address: user_vault }
                .transfer(token, receiver, amount);
            user_vault_balance.write(user_vault_balance.read() - amount);
        }


        fn pause_vault(ref self: ContractState) {
            let caller = get_caller_address();
            let user_vault = self.user_vault.entry(caller).read();
            let is_whitelisted = self.check_is_whitelisted(caller);

            assert!(
                self.is_user_vault_paused.entry(caller).entry(user_vault).read() == false,
                "pause_vault: vault paused"
            );
            assert!(is_whitelisted, "pause_vault: not whitelisted");

            self.is_user_vault_paused.entry(caller).entry(user_vault).write(true);
            self.emit(VaultPaused { user: caller, paused_at: get_block_timestamp() });
        }


        fn reactivate_vault(ref self: ContractState) {
            let caller = get_caller_address();
            let user_vault = self.user_vault.entry(caller).read();
            let is_whitelisted = self.check_is_whitelisted(caller);
            let is_user_vault_paused = self
                .is_user_vault_paused
                .entry(caller)
                .entry(user_vault)
                .read();

            assert!(is_whitelisted, "reactivate_vault: not whitelisted");
            assert!(is_user_vault_paused == true, "reactivate_vault: vault active");

            self.is_user_vault_paused.entry(caller).entry(user_vault).write(false);
            self.emit(VaultReactivated { user: caller, reactivated_at: get_block_timestamp() });
        }


        fn get_user_balance(self: @ContractState, account: ContractAddress) -> u256 {
            let user_vault = self.user_vault.entry(account).read();
            self.user_vault_balance.entry(account).entry(user_vault).read()
        }

        fn get_user_vault_balance(
            self: @ContractState, user: ContractAddress, token: ContractAddress
        ) -> (ContractAddress, u256) {
            let user_vault = self.user_vault.entry(user).read();
            IMainVaultTraitDispatcher { contract_address: user_vault }
                .get_vault_balance(user_vault, token)
        }


        fn get_linked_accounts(
            self: @ContractState, account: ContractAddress
        ) -> Array<ContractAddress> {
            let whitelisted_accounts = self.user_whitelisted_accounts.entry(account);
            let mut arr = array![];
            let mut i = 0;

            loop {
                if i > whitelisted_accounts.len() {
                    break;
                }
                let mut whitelisted_account = whitelisted_accounts.at(i).read();
                arr.append(whitelisted_account);
                i += 1;
            };
            arr
        }

        fn get_total_users(self: @ContractState) -> u64 {
            self.users.len()
        }

        fn get_total_deposits(self: @ContractState) -> u256 {
            self.total_deposits.read()
        }

        fn get_total_withdrawals(self: @ContractState) -> u256 {
            self.total_withdrawals.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }

        fn check_account_is_whitelisted(self: @ContractState, account: ContractAddress) -> bool {
            let caller = get_caller_address();
            self.is_whitelisted.entry(caller).entry(account).read()
        }

        fn update_vault_classhash(ref self: ContractState, new_classhash: ClassHash) {
            self.ownable.assert_only_owner();
            assert!(new_classhash.is_non_zero(), "update_vault_classhash: invalid classhash");
            self.vault_classhash.write(new_classhash);
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn check_is_whitelisted(ref self: ContractState, account: ContractAddress) -> bool {
            let caller = get_caller_address();
            self.is_whitelisted.entry(caller).entry(account).read()
        }

        fn check_vault_is_paused(ref self: ContractState) -> bool {
            let caller = get_caller_address();
            let user_vault = self.user_vault.entry(caller).read();
            self.is_user_vault_paused.entry(caller).entry(user_vault).read()
        }
    }
}
