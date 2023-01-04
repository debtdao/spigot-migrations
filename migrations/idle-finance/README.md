# Idle Finance Migration Guide

The files contained in this directory enable the deployment of a Secured Line of Credit for Idle Finance's Fee Collector.

All relevant contract addresses and parameters for the migration are located in the [settings.yaml](./settings.yml) file.

Detailed documentation of the migration process can be found in the [Idle Migration Guide](./GUIDE.md).

## Testing

Tests require the `ETH_RPC_URL` to be set with an RPC URL of a mainnet archival node as some tests require a fork of Ethereum's mainnet.

```
forge test --match-contract IdleMigrationTest -vv --gas-report
```

## Migration details

A potential vulnerability in the migration process is manipulation of the FeeCollector's beneficiaries list.  While unlikely, it's possible that the FeeCollector's admin could update the beneficiaries list and the allocations after the migration contract has been deployed. As a result, the migration contract needs to account for the possibility that the list of beneficiaries will be different at the time the migration is executed, compared to when the migration code was written.  In order to account for this, the migration contract uses an internal function `_setBeneficiariesAndAllocations()` that replaces and/or removes any addresses and allocations that do not conform to the prior arrangement.

The following diagram illustrates how the algorithm replaces and updates the beneficiaries, by taking into account whether or not a duplicate is present in the array.  In this example, we want to replace index `2` (the address `0xCcCcC`) with the address `0xEeEeE`, which has a duplicate address present at index `4`.

```
T 0:
index   address     allocation
    0   0xAaAaA     0
    1   0xBbBbB     50
    2   0xCcCcC     10          <===== 0xEeEeE
    3   0xDdDdD     20
    4   0xEeEeE     15
    5   0xFfFfF     15
```

Because we know our list of desired beneficiaries has a length of 4, and given that it's too gas-inefficient to remove elements from the end of the array, we simply set any beneficiaries with index `> 3` to have an allocation of `0`.

```
T 1:
index   address     allocation
    0   0xAaAaA     0
    1   0xBbBbB     70
    2   0xCcCcC     10          <===== 0xEeEeE
    3   0xDdDdD     20
    ------------------
    4   0xEeEeE     0
    5   0xFfFfF     0
```

Next, we want to remove the duplicate from the existing list of beneficiaries by replacing it with a dynamically derived (and non-existent) account.

```
T 2:
index   address     allocation
    0   0xAaAaA     0
    1   0xBbBbB     70
    2   0xCcCcC     10          <===== 0xEeEeE
    3   0xDdDdD     20
    ------------------
    4   0x%4$3@     0           <===== replaced
    5   0xFfFfF     0
```

Finally, we can replace the exist at the index of interest with the one we want.

```
T 3:
index   address     allocation
    0   0xAaAaA     0
    1   0xBbBbB     70
    2   0xEeEeE     10 <===== 
    3   0xDdDdD     20
    ------------------
    4   0x%4$3@     0 
    5   0xFfFfF     0
```

This process ensures that the final result, ie the list of beneficiaries and their allocations, conforms to the agreed upon breakdown.

## Deployment

### Local Environment

// coming soon

### Mainnet

// coming soon