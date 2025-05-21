use starknet::{ContractAddress, get_contract_address};
use strkfarm_vesu::helpers::constants;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, ERC20ABIDispatcher, ERC20ABIDispatcherTrait
};
use strkfarm_vesu::interfaces::oracle::{
    IPriceOracle, IPriceOracleDispatcher, IPriceOracleDispatcherTrait
};
use strkfarm_vesu::helpers::safe_decimal_math;
use strkfarm_vesu::helpers::ERC20Helper;

#[derive(Drop, Clone, Serde)]
pub struct Route {
    pub token_from: ContractAddress,
    pub token_to: ContractAddress,
    pub exchange_address: ContractAddress,
    pub percent: u128,
    pub additional_swap_params: Array<felt252>,
}

#[starknet::interface]
pub trait IAvnu<TContractState> {
    fn multi_route_swap(
        ref self: TContractState,
        token_from_address: ContractAddress,
        token_from_amount: u256,
        token_to_address: ContractAddress,
        token_to_amount: u256,
        token_to_min_amount: u256,
        beneficiary: ContractAddress,
        integrator_fee_amount_bps: u128,
        integrator_fee_recipient: ContractAddress,
        routes: Array<Route>,
    ) -> bool;
}

#[derive(Drop, Clone, Serde)]
pub struct AvnuMultiRouteSwap {
    pub token_from_address: ContractAddress,
    pub token_from_amount: u256,
    pub token_to_address: ContractAddress,
    pub token_to_amount: u256,
    pub token_to_min_amount: u256,
    pub beneficiary: ContractAddress,
    pub integrator_fee_amount_bps: u128,
    pub integrator_fee_recipient: ContractAddress,
    pub routes: Array<Route>
}

#[derive(Drop, Clone, Serde)]
pub struct SwapInfoMinusAmount {
    pub token_from_address: ContractAddress,
    pub token_to_address: ContractAddress,
    pub beneficiary: ContractAddress,
    pub integrator_fee_amount_bps: u128,
    pub integrator_fee_recipient: ContractAddress,
    pub routes: Array<Route>
}

// todo assert min price amount using oracle values
// else it could lead to an attacker using bad DEX instead during claim

#[generate_trait]
pub impl AvnuMultiRouteSwapImpl of AvnuMultiRouteSwapTrait {
    fn swap(self: AvnuMultiRouteSwap, oracle: IPriceOracleDispatcher) -> u256 {
        let amount_out = avnuSwap(
            SwapInfoMinusAmount {
                token_from_address: self.token_from_address,
                token_to_address: self.token_to_address,
                beneficiary: self.beneficiary,
                integrator_fee_amount_bps: self.integrator_fee_amount_bps,
                integrator_fee_recipient: self.integrator_fee_recipient,
                routes: self.routes
            },
            self.token_from_amount,
            self.token_to_amount,
            self.token_to_min_amount
        );

        assert_max_slippage(
            self.token_from_address,
            self.token_from_amount,
            self.token_to_address,
            amount_out,
            constants::MAX_SLIPPAGE_BPS,
            oracle
        );

        amount_out
    }
}


// #[generate_trait]
// pub impl SwapInfoMinusAmountImpl of SwapInfoMinusAmountTrait {
//     fn swap(
//         self: SwapInfoMinusAmount,
//         token_from_amount: u256,
//         token_to_amount: u256,
//         token_to_min_amount: u256,
//         oracle: IPriceOracleDispatcher
//     ) -> u256 {
//         let amount_out = avnuSwap(
//             self, 
//             token_from_amount, 
//             token_to_amount, 
//             token_to_min_amount
//         );

//         assert_max_slippage(
//             self.token_from_address,
//             token_from_amount,
//             self.token_to_address,
//             amount_out,
//             100, // 1%
//             oracle
//         );
//     }
// }

fn avnuSwap(
    swapInfo: SwapInfoMinusAmount,
    token_from_amount: u256,
    token_to_amount: u256,
    token_to_min_amount: u256
) -> u256 {
    let toToken = ERC20ABIDispatcher { contract_address: swapInfo.token_to_address };
    let this = get_contract_address();
    let pre_bal = toToken.balanceOf(this);

    assert(swapInfo.integrator_fee_amount_bps == 0, 'require avnu fee bps 0');
    assert(swapInfo.beneficiary == this, 'invalid swap beneficiary');

    let avnuAddress = constants::AVNU_EX();
    IERC20Dispatcher { contract_address: swapInfo.token_from_address }
        .approve(avnuAddress, token_from_amount);
    let swapped = IAvnuDispatcher { contract_address: avnuAddress }
        .multi_route_swap(
            swapInfo.token_from_address,
            token_from_amount,
            swapInfo.token_to_address,
            token_to_amount,
            token_to_min_amount,
            swapInfo.beneficiary,
            swapInfo.integrator_fee_amount_bps,
            swapInfo.integrator_fee_recipient,
            swapInfo.routes
        );
    assert(swapped, 'Swap failed');

    let post_bal = toToken.balanceOf(this);
    let amount = post_bal - pre_bal;
    assert(amount > 0, 'invalid to amount');

    amount
}

pub fn assert_max_slippage(
    token_from: ContractAddress,
    token_from_amount: u256,
    token_to: ContractAddress,
    token_to_amount: u256,
    max_slippage_bps: u32,
    oracle: IPriceOracleDispatcher
) {
    // from token usd value
    let from_price = oracle.get_price(token_from);
    let from_decimals = ERC20Helper::decimals(token_from);
    let from_usd = safe_decimal_math::mul_decimals(
        from_price.into(), token_from_amount, from_decimals
    );

    // to token usd value
    let to_price = oracle.get_price(token_to);
    let to_decimals = ERC20Helper::decimals(token_to);
    let to_usd = safe_decimal_math::mul_decimals(to_price.into(), token_to_amount, to_decimals);

    // max slippage
    let max_slippage = safe_decimal_math::mul_decimals(from_usd, max_slippage_bps.into(), 4);

    assert(to_usd >= (from_usd - max_slippage), 'Swap:: Slippage too high');
}

#[cfg(test)]
mod test_swaps {
    use strkfarm_vesu::tests::constants;
    use starknet::{
        ContractAddress, get_contract_address, get_block_timestamp,
        contract_address::contract_address_const
    };
    use strkfarm_vesu::interfaces::oracle::{
        IPriceOracle, IPriceOracleDispatcher, IPriceOracleDispatcherTrait
    };

    #[test]
    #[fork("mainnet_usdc_large")]
    fn test_max_slippage_same_tokens() {
        let oracle = IPriceOracleDispatcher { contract_address: constants::Oracle() };
        let token_from = constants::USDC_ADDRESS();
        let token_to = constants::USDC_ADDRESS();
        let token_from_amount = 1000000000000000000;
        let token_to_amount = 1000000000000000000;
        let max_slippage_bps = 100; // 1%

        super::assert_max_slippage(
            token_from, token_from_amount, token_to, token_to_amount, max_slippage_bps, oracle
        );
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    fn test_max_slippage_diff_tokens_should_pass() {
        let oracle = IPriceOracleDispatcher { contract_address: constants::Oracle() };
        let token_from = constants::USDC_ADDRESS();
        let token_to = constants::STRK_ADDRESS();
        let token_from_amount = 10000000; // 10 USDC
        let token_to_amount = 10000000000000000000; // 10 STRK
        let max_slippage_bps = 100;

        super::assert_max_slippage(
            token_from, token_from_amount, token_to, token_to_amount, max_slippage_bps, oracle
        );
    }

    #[test]
    #[fork("mainnet_usdc_large")]
    #[should_panic(expected: ('Swap:: Slippage too high',))]
    fn test_max_slippage_diff_tokens_should_fail() {
        let oracle = IPriceOracleDispatcher { contract_address: constants::Oracle() };
        let token_from = constants::USDC_ADDRESS();
        let token_to = constants::STRK_ADDRESS();
        let token_from_amount = 11000000; // 11 USDC
        let token_to_amount = 10000000000000000000; // 10 STRK
        let max_slippage_bps = 100;

        super::assert_max_slippage(
            token_from, token_from_amount, token_to, token_to_amount, max_slippage_bps, oracle
        );
    }
}
