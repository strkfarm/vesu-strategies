use starknet::ContractAddress;
use starknet::contract_address::contract_address_const;

pub const BASIS_POINTS_FACTOR: u32 = 10000;
pub const TWO_POWER_128: u128 = 0xffffffffffffffffffffffffffffffff;
pub const TWO_POWER_256: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

pub const MAX_SLIPPAGE_BPS: u32 = 300; // 3%

// mainnet address
pub fn STRK_ADDRESS() -> ContractAddress {
    contract_address_const::<0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>()
}

pub fn AVNU_EX() -> ContractAddress {
    contract_address_const::<0x04270219d365d6b017231b52e92b3fb5d7c8378b05e9abc97724537a80e93b0f>()
}
