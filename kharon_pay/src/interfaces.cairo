use starknet::ContractAddress;

#[starknet::interface]
pub trait IKharonPay<TContractState> {
    fn receive_payment(
        ref self: TContractState,
        token: ContractAddress,
        amount: u256,
        reference: ByteArray,
        user: ByteArray,
    );
    fn add_supported_token(ref self: TContractState, token: ContractAddress);
    fn withdraw(
        ref self: TContractState, token: ContractAddress, receiver: ContractAddress, amount: u256,
    );
    fn remove_supported_token(ref self: TContractState, token: ContractAddress);
    fn pause_system(ref self: TContractState);
    fn unpause_system(ref self: TContractState);
    fn is_supported_token(self: @TContractState, token: ContractAddress) -> bool;
    fn get_system_status(self: @TContractState) -> bool;
    fn get_supported_tokens(self: @TContractState) -> Array<ContractAddress>;
}
