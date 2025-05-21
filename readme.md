# Vesu Strategies
This MIT-licensed repository is dedicated to Vesu, a platform for lending on Starknet. Currently, it features a single implemented strategy: the Vesu Rebalancing Strategy — a smart contract-based mechanism that dynamically rebalances asset allocations to different Vesu pools to maximize returns.

## Strategies
| Strategy Name | Documentation |
|----------------|---------------|
| Vesu Rebalancing | [Documentation](https://github.com/strkfarm/vesu-strategies/blob/main/src/strategies/vesu_rebalance/README.md) |
|||

## Develop
### Requirements
1. Scarb 2.8.4
2. snforge 0.38.3

### Build
```scarb build```

### Test
1. Export `MAINNET_RPC_URL` url to allow fork testing
2. ```scarb test```

### Audit report
TBD

## Credits
Developed by Unwrap Labs (STRKFarm) and Vesu.   
  
Technical Contributors:
1. [Akiraonstarknet](https://github.com/akiraonstarknet)
2. [Ariyan](https://github.com/0x-minato)