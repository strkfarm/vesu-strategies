use starknet::ContractAddress;

pub trait ISwapMod<TSettings> {
    fn swap(
        self: TSettings, 
        from_token: ContractAddress,
        to_token: ContractAddress,
        amount_in: u256,
        min_amount_out: u256,
        receiver: ContractAddress,
    ) -> u256;

    fn get_amounts_in(
        self: TSettings,
        amount_out: u256,
        path: Array<ContractAddress>,
    ) -> Array<u256>;
    
    fn get_amounts_out(
        self: TSettings,
        amount_in: u256,
        path: Array<ContractAddress>,
    ) -> Array<u256>;

    fn assert_valid(self: TSettings);
}
