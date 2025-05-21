use strkfarm_vesu::helpers::safe_decimal_math;
use starknet::ContractAddress;
use strkfarm_vesu::helpers::ERC20Helper;
use strkfarm_vesu::helpers::constants;

#[derive(Drop, Copy, Serde)]
pub struct BorrowData {
    pub token: ContractAddress,
    pub borrow_factor: u256 // 18 decimals
}

pub trait MMTokenTrait<T, TSettings> {
    // used for hf calculation
    fn collateral_value(self: @T, state: TSettings, user: ContractAddress) -> u256;
    fn required_value(self: @T, state: TSettings, user: ContractAddress) -> u256;
    // collateral value as required by HF
    fn calculate_collateral_value(self: @T, state: TSettings, amount: u256) -> u256;
    fn price(self: @T, state: TSettings) -> (u256, u8);
    fn underlying_asset(self: @T, state: TSettings) -> ContractAddress;
    fn get_borrow_data(self: @T, state: TSettings) -> BorrowData;
}

pub trait ILendMod<TSettings, T> {
    fn deposit(self: TSettings, token: ContractAddress, amount: u256);
    fn withdraw(self: TSettings, token: ContractAddress, amount: u256);
    fn borrow(self: TSettings, token: ContractAddress, amount: u256);
    fn repay(self: TSettings, token: ContractAddress, amount: u256);
    fn health_factor(
        self: TSettings,
        user: ContractAddress,
        deposits: Array<T>, 
        borrows: Array<T>
    ) -> u32;
    fn assert_valid(self: TSettings);
    fn max_borrow_amount(
        self: TSettings,
        deposit_token: T,
        deposit_amount: u256,
        borrow_token: T,
        min_hf: u32 
    ) -> u256;
    fn min_borrow_required(
        self: TSettings,
        token: ContractAddress,
    ) -> u256;
    fn deposit_amount(self: TSettings, asset: ContractAddress, user: ContractAddress) -> u256;
    fn borrow_amount(self: TSettings, asset: ContractAddress, user: ContractAddress) -> u256;
}
