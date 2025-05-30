// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts for Cairo v0.18.0 (token/erc20/extensions/erc4626/erc4626.cairo)

/// # ERC4626 Component
///
/// ADD MEEEEEEEEEEEEEEEEE AHHHH
#[starknet::component]
pub mod ERC4626Component {
    use core::num::traits::{Bounded, Zero};
    use openzeppelin::token::erc20::ERC20Component::InternalImpl as ERC20InternalImpl;
    use openzeppelin::token::erc20::ERC20Component;
    use strkfarm_vesu::interfaces::IERC4626::{
        IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait
    };
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20Metadata
    };
    use strkfarm_vesu::helpers::Math::{Rounding, u256_mul_div, power};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // The default values are only used when the DefaultConfig
    // is in scope in the implementing contract.
    pub const DEFAULT_UNDERLYING_DECIMALS: u8 = 18;
    pub const DEFAULT_DECIMALS_OFFSET: u8 = 0;

    #[storage]
    pub struct Storage {
        ERC4626_asset: ContractAddress
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Deposit {
        #[key]
        pub sender: ContractAddress,
        #[key]
        pub owner: ContractAddress,
        pub assets: u256,
        pub shares: u256
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Withdraw {
        #[key]
        pub sender: ContractAddress,
        #[key]
        pub receiver: ContractAddress,
        #[key]
        pub owner: ContractAddress,
        pub assets: u256,
        pub shares: u256
    }

    pub mod Errors {
        pub const EXCEEDED_MAX_DEPOSIT: felt252 = 'ERC4626: exceeds max deposit';
        pub const EXCEEDED_MAX_MINT: felt252 = 'ERC4626: exceeds max mint';
        pub const EXCEEDED_MAX_WITHDRAW: felt252 = 'ERC4626: exceeds max withdraw';
        pub const EXCEEDED_MAX_REDEEM: felt252 = 'ERC4626: exceeds max redeem';
        pub const TOKEN_TRANSFER_FAILED: felt252 = 'ERC4626: token transfer failed';
        pub const INVALID_ASSET_ADDRESS: felt252 = 'ERC4626: asset address set to 0';
        pub const DECIMALS_OVERFLOW: felt252 = 'ERC4626: decimals overflow';
    }

    /// Constants expected to be defined at the contract level used to configure the component
    /// behaviour.
    ///
    /// ADD ME...
    pub trait ImmutableConfig {
        const UNDERLYING_DECIMALS: u8;
        const DECIMALS_OFFSET: u8;

        fn validate() {
            assert(
                Bounded::MAX - Self::UNDERLYING_DECIMALS >= Self::DECIMALS_OFFSET,
                Errors::DECIMALS_OVERFLOW
            )
        }
    }

    /// Adjustments for fees expected to be defined on the contract level.
    /// Defaults to no entry or exit fees.
    /// To transfer fees, this trait needs to be coordinated with ERC4626Component::ERC4626Hooks.
    pub trait FeeConfigTrait<TContractState> {
        fn adjust_deposit(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            assets
        }

        fn adjust_mint(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            assets
        }

        fn adjust_withdraw(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            assets
        }

        fn adjust_redeem(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            assets
        }
    }

    /// Sets custom limits to the target exchange type and is expected to be defined at the contract
    /// level.
    pub trait LimitConfigTrait<TContractState> {
        fn deposit_limit(
            self: @ComponentState<TContractState>, receiver: ContractAddress
        ) -> Option::<u256> {
            Option::None
        }

        fn mint_limit(
            self: @ComponentState<TContractState>, receiver: ContractAddress
        ) -> Option::<u256> {
            Option::None
        }

        fn withdraw_limit(
            self: @ComponentState<TContractState>, owner: ContractAddress
        ) -> Option::<u256> {
            Option::None
        }

        fn redeem_limit(
            self: @ComponentState<TContractState>, owner: ContractAddress
        ) -> Option::<u256> {
            Option::None
        }
    }

    /// Allows contracts to hook logic into deposit and withdraw transactions.
    /// This is where contracts can transfer fees.
    pub trait ERC4626HooksTrait<TContractState> {
        fn before_withdraw(ref self: ComponentState<TContractState>, assets: u256, shares: u256) {}
        fn after_deposit(ref self: ComponentState<TContractState>, assets: u256, shares: u256) {}
    }

    #[embeddable_as(ERC4626Impl)]
    impl ERC4626<
        TContractState,
        +HasComponent<TContractState>,
        impl Fee: FeeConfigTrait<TContractState>,
        impl Limit: LimitConfigTrait<TContractState>,
        impl Hooks: ERC4626HooksTrait<TContractState>,
        impl Immutable: ImmutableConfig,
        impl ERC20: ERC20Component::HasComponent<TContractState>,
        +ERC20Component::ERC20HooksTrait<TContractState>,
        +Drop<TContractState>
    > of IERC4626<ComponentState<TContractState>> {
        /// Returns the address of the underlying token used for the Vault for accounting,
        /// depositing, and withdrawing.
        fn asset(self: @ComponentState<TContractState>) -> ContractAddress {
            self.ERC4626_asset.read()
        }

        /// Returns the total amount of the underlying asset that is “managed” by Vault.
        fn total_assets(self: @ComponentState<TContractState>) -> u256 {
            let this = starknet::get_contract_address();
            let erc20_component = get_dep_component!(self, ERC20);
            erc20_component.balance_of(this)
        }

        /// Returns the amount of shares that the Vault would exchange for the amount of assets
        /// provided, in an ideal scenario where all the conditions are met.
        fn convert_to_shares(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            self._convert_to_shares(assets, Rounding::Floor)
        }

        /// Returns the amount of assets that the Vault would exchange for the amount of shares
        /// provided, in an ideal scenario where all the conditions are met.
        fn convert_to_assets(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            self._convert_to_assets(shares, Rounding::Floor)
        }

        /// Returns the maximum amount of the underlying asset that can be deposited into the Vault
        /// for the receiver, through a deposit call.
        /// If the `LimitConfigTrait` is not defined for deposits, returns 2 ** 256 - 1.
        fn max_deposit(self: @ComponentState<TContractState>, receiver: ContractAddress) -> u256 {
            match Limit::deposit_limit(self, receiver) {
                Option::Some(limit) => limit,
                Option::None => Bounded::MAX
            }
        }

        /// Allows an on-chain or off-chain user to simulate the effects of their deposit at the
        /// current block, given current on-chain conditions.
        /// If the `FeeConfigTrait` is not defined for deposits, returns the full amount of shares.
        fn preview_deposit(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            let adjusted_assets = Fee::adjust_deposit(self, assets);
            self._convert_to_shares(adjusted_assets, Rounding::Floor)
        }

        /// Mints Vault shares to `receiver` by depositing exactly `assets` of underlying tokens.
        /// Returns the amount of newly-minted shares.
        ///
        /// Requirements:
        /// - `assets` is less than or equal to the max deposit amount for `receiver`.
        ///
        /// Emits a `Deposit` event.
        fn deposit(
            ref self: ComponentState<TContractState>, assets: u256, receiver: ContractAddress
        ) -> u256 {
            let max_assets = self.max_deposit(receiver);
            assert(assets <= max_assets, Errors::EXCEEDED_MAX_DEPOSIT);

            let shares = self.preview_deposit(assets);
            let caller = starknet::get_caller_address();
            self._deposit(caller, receiver, assets, shares);

            shares
        }

        /// Returns the maximum amount of the Vault shares that can be minted for `receiver` through
        /// a `mint` call.
        /// If the `LimitConfigTrait` is not defined for mints, returns 2 ** 256 - 1.
        fn max_mint(self: @ComponentState<TContractState>, receiver: ContractAddress) -> u256 {
            match Limit::mint_limit(self, receiver) {
                Option::Some(limit) => limit,
                Option::None => Bounded::MAX
            }
        }

        /// Allows an on-chain or off-chain user to simulate the effects of their mint at the
        /// current block, given current on-chain conditions.
        /// If the `FeeConfigTrait` is not defined for mints, returns the full amount of assets.
        fn preview_mint(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            let raw_amount = self._convert_to_assets(shares, Rounding::Ceil);
            Fee::adjust_mint(self, raw_amount)
        }

        /// Mints exactly Vault `shares` to `receiver` by depositing amount of underlying tokens.
        /// Returns the amount deposited assets.
        ///
        /// Requirements:
        /// - `shares` is less than or equal to the max shares amount for `receiver`.
        ///
        /// Emits a `Deposit` event.
        fn mint(
            ref self: ComponentState<TContractState>, shares: u256, receiver: ContractAddress
        ) -> u256 {
            let max_shares = self.max_mint(receiver);
            assert(shares <= max_shares, Errors::EXCEEDED_MAX_MINT);

            let assets = self.preview_mint(shares);
            let caller = starknet::get_caller_address();
            self._deposit(caller, receiver, assets, shares);

            assets
        }

        /// Returns the maximum amount of the underlying asset that can be withdrawn from the owner
        /// balance in the Vault, through a `withdraw` call.
        /// If the `LimitConfigTrait` is not defined for withdraws, returns the full balance of
        /// assets for `owner` (converted to shares).
        fn max_withdraw(self: @ComponentState<TContractState>, owner: ContractAddress) -> u256 {
            match Limit::withdraw_limit(self, owner) {
                Option::Some(limit) => limit,
                Option::None => {
                    let mut erc20_disp = IERC20Dispatcher {
                        contract_address: starknet::get_contract_address()
                    };
                    let owner_bal = erc20_disp.balance_of(owner);
                    self._convert_to_assets(owner_bal, Rounding::Floor)
                }
            }
        }

        /// Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the
        /// current block, given current on-chain conditions.
        /// If the `FeeConfigTrait` is not defined for withdraws, returns the full amount of shares.
        fn preview_withdraw(self: @ComponentState<TContractState>, assets: u256) -> u256 {
            let adjusted_assets = Fee::adjust_withdraw(self, assets);
            self._convert_to_shares(adjusted_assets, Rounding::Ceil)
        }

        /// Burns shares from `owner` and sends exactly `assets` of underlying tokens to `receiver`.
        ///
        /// Requirements:
        /// - `assets` is less than or equal to the max withdraw amount of `owner`.
        ///
        /// Emits a `Withdraw` event.
        fn withdraw(
            ref self: ComponentState<TContractState>,
            assets: u256,
            receiver: ContractAddress,
            owner: ContractAddress
        ) -> u256 {
            let max_assets = self.max_withdraw(owner);
            assert(assets <= max_assets, Errors::EXCEEDED_MAX_WITHDRAW);

            let shares = self.preview_withdraw(assets);
            let caller = starknet::get_caller_address();
            self._withdraw(caller, receiver, owner, assets, shares);

            shares
        }

        /// Returns the maximum amount of Vault shares that can be redeemed from the owner balance
        /// in the Vault, through a `redeem` call.
        /// If the `LimitConfigTrait` is not defined for redeems, returns the full balance of assets
        /// for `owner`.
        fn max_redeem(self: @ComponentState<TContractState>, owner: ContractAddress) -> u256 {
            match Limit::redeem_limit(self, owner) {
                Option::Some(limit) => limit,
                Option::None => {
                    let mut erc20_disp = IERC20Dispatcher {
                        contract_address: starknet::get_contract_address()
                    };
                    erc20_disp.balance_of(owner)
                }
            }
        }

        /// Allows an on-chain or off-chain user to simulate the effects of their redeemption at the
        /// current block, given current on-chain conditions.
        /// If the `FeeConfigTrait` is not defined for redeems, returns the full amount of assets.
        fn preview_redeem(self: @ComponentState<TContractState>, shares: u256) -> u256 {
            let raw_amount = self._convert_to_assets(shares, Rounding::Floor);
            Fee::adjust_redeem(self, raw_amount)
        }

        /// Burns exactly `shares` from `owner` and sends assets of underlying tokens to `receiver`.
        ///
        /// Requirements:
        /// - `shares` is less than or equal to the max redeem amount of `owner`.
        ///
        /// Emits a `Withdraw` event.
        fn redeem(
            ref self: ComponentState<TContractState>,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress
        ) -> u256 {
            let max_shares = self.max_redeem(owner);
            assert(shares <= max_shares, Errors::EXCEEDED_MAX_REDEEM);

            let assets = self.preview_redeem(shares);
            let caller = starknet::get_caller_address();
            self._withdraw(caller, receiver, owner, assets, shares);

            assets
        }
    }

    #[embeddable_as(ERC4626MetadataImpl)]
    impl ERC4626Metadata<
        TContractState,
        +HasComponent<TContractState>,
        impl Immutable: ImmutableConfig,
        impl ERC20: ERC20Component::HasComponent<TContractState>,
    > of IERC20Metadata<ComponentState<TContractState>> {
        /// Returns the name of the token.
        fn name(self: @ComponentState<TContractState>) -> ByteArray {
            let erc20_component = get_dep_component!(self, ERC20);
            erc20_component.ERC20_name.read()
        }

        /// Returns the ticker symbol of the token, usually a shorter version of the name.
        fn symbol(self: @ComponentState<TContractState>) -> ByteArray {
            let erc20_component = get_dep_component!(self, ERC20);
            erc20_component.ERC20_symbol.read()
        }

        /// Returns the cumulative number of decimals which includes both the underlying and offset
        /// decimals.
        /// Both of which must be defined in the `ImmutableConfig` inside the implementing contract.
        fn decimals(self: @ComponentState<TContractState>) -> u8 {
            Immutable::UNDERLYING_DECIMALS + Immutable::DECIMALS_OFFSET
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl Hooks: ERC4626HooksTrait<TContractState>,
        impl Immutable: ImmutableConfig,
        impl ERC20: ERC20Component::HasComponent<TContractState>,
        +FeeConfigTrait<TContractState>,
        +LimitConfigTrait<TContractState>,
        +ERC20Component::ERC20HooksTrait<TContractState>,
        +Drop<TContractState>
    > of InternalTrait<TContractState> {
        /// Validates the `ImmutableConfig` constants and sets the `asset_address` to the vault.
        /// This should be set in the contract's constructor.
        ///
        /// Requirements:
        /// - `asset_address` cannot be the zero address.
        fn initializer(ref self: ComponentState<TContractState>, asset_address: ContractAddress) {
            ImmutableConfig::validate();
            assert(!asset_address.is_zero(), Errors::INVALID_ASSET_ADDRESS);
            self.ERC4626_asset.write(asset_address);
        }

        /// Business logic for `deposit` and `mint`.
        /// Transfers `assets` from `caller` to the Vault contract then mints `shares` to
        /// `receiver`.
        /// Fees can be transferred in the `ERC4626Hooks::after_deposit` hook which is executed
        /// after the business logic.
        ///
        /// Requirements:
        /// - `ERC20::transfer_from` must return true.
        ///
        /// Emits two `ERC20::Transfer` events (`ERC20::mint` and `ERC20::transfer_from`).
        /// Emits a `Deposit` event.
        fn _deposit(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256
        ) {
            // Transfer assets first
            let this = starknet::get_contract_address();
            let asset_dispatcher = IERC20Dispatcher { contract_address: self.ERC4626_asset.read() };
            assert(
                asset_dispatcher.transfer_from(caller, this, assets), Errors::TOKEN_TRANSFER_FAILED
            );

            // Mint shares after transferring assets
            let mut erc20_component = get_dep_component_mut!(ref self, ERC20);
            erc20_component.mint(receiver, shares);
            self.emit(Deposit { sender: caller, owner: receiver, assets, shares });

            // After deposit hook
            Hooks::after_deposit(ref self, assets, shares);
        }

        /// Business logic for `withdraw` and `redeem`.
        /// Burns `shares` from `owner` and then transfers `assets` to `receiver`.
        /// Fees can be transferred in the `ERC4626Hooks::before_withdraw` hook which is executed
        /// before the business logic.
        ///
        /// Requirements:
        /// - `ERC20::transfer` must return true.
        ///
        /// Emits two `ERC20::Transfer` events (`ERC20::burn` and `ERC20::transfer`).
        /// Emits a `Withdraw` event.
        fn _withdraw(
            ref self: ComponentState<TContractState>,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256
        ) {
            // Before withdraw hook
            Hooks::before_withdraw(ref self, assets, shares);

            // Burn shares first
            let mut erc20_component = get_dep_component_mut!(ref self, ERC20);
            if (caller != owner) {
                erc20_component._spend_allowance(owner, caller, shares);
            }
            erc20_component.burn(owner, shares);

            // Transfer assets after burn
            let asset_dispatcher = IERC20Dispatcher { contract_address: self.ERC4626_asset.read() };
            assert(asset_dispatcher.transfer(receiver, assets), Errors::TOKEN_TRANSFER_FAILED);

            self.emit(Withdraw { sender: caller, receiver, owner, assets, shares });
        }

        /// Internal conversion function (from assets to shares) with support for `rounding`
        /// direction.
        fn _convert_to_shares(
            self: @ComponentState<TContractState>, assets: u256, rounding: Rounding
        ) -> u256 {
            let this = starknet::get_contract_address();
            let mut erc20_disp = IERC20Dispatcher { contract_address: this };
            let total_supply = erc20_disp.total_supply();

            // allows to call the overriden impl of the contract
            let disp = IERC4626Dispatcher { contract_address: this };

            u256_mul_div(
                assets,
                total_supply + power(10, Immutable::DECIMALS_OFFSET.into()),
                disp.total_assets() + 1,
                rounding
            )
        }

        /// Internal conversion function (from shares to assets) with support for `rounding`
        /// direction.
        fn _convert_to_assets(
            self: @ComponentState<TContractState>, shares: u256, rounding: Rounding
        ) -> u256 {
            let this = starknet::get_contract_address();
            let mut erc20_disp = IERC20Dispatcher { contract_address: this };
            let total_supply = erc20_disp.total_supply();

            // allows to call the overriden impl of the contract
            let disp = IERC4626Dispatcher { contract_address: this };

            u256_mul_div(
                shares,
                disp.total_assets() + 1,
                total_supply + power(10, Immutable::DECIMALS_OFFSET.into()),
                rounding
            )
        }
    }
}

///
/// Default (empty) traits
///

pub impl ERC4626HooksEmptyImpl<
    TContractState
> of ERC4626Component::ERC4626HooksTrait<TContractState> {}
pub impl ERC4626DefaultNoFees<TContractState> of ERC4626Component::FeeConfigTrait<TContractState> {}
pub impl ERC4626DefaultLimits<
    TContractState
> of ERC4626Component::LimitConfigTrait<TContractState> {}

/// Implementation of the default `ERC4626Component::ImmutableConfig`.
///
/// See
/// https://github.com/starknet-io/SNIPs/blob/963848f0752bde75c7087c2446d83b7da8118b25/SNIPS/snip-107.md#defaultconfig-implementation
///
/// The default underlying decimals is set to `18`.
/// The default decimals offset is set to `0`.
pub impl DefaultConfig of ERC4626Component::ImmutableConfig {
    const UNDERLYING_DECIMALS: u8 = ERC4626Component::DEFAULT_UNDERLYING_DECIMALS;
    const DECIMALS_OFFSET: u8 = ERC4626Component::DEFAULT_DECIMALS_OFFSET;
}
