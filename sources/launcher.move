
module launcher::deployer {
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use std::signer;
    use std::string::{String};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{ ConstructorRef };
    use std::option;

    // Error Codes 
    const INSUFFICIENT_APT_BALANCE: u64 = 1;
    const ERROR_NOT_INITIALIZED: u64 = 2;
    const ERROR_INVALID_ACCOUNT: u64 = 3;

    struct Launcher {}

    struct Config has key {
        owner: address,
    }

    #[event]
    struct NewOwnerEvent has drop, store { new_owner: address }
    fun emit_new_owner_event(new_owner: address) {
        event::emit<NewOwnerEvent>(NewOwnerEvent { new_owner })
    }

    entry public fun init(caller: &signer, owner: address){
        assert!(signer::address_of(caller) == @launcher, ERROR_INVALID_ACCOUNT);
        move_to(caller, Config { owner })
    }

    public fun fungible(
        deployer: &signer,
        constructor_ref: &ConstructorRef,
        name: String,
        symbol: String,
        decimals: u8,
        icon: String,
        project: String,
    ) {
        // the deployer must have enough APT to pay for the fee
        // assert!(
        //     coin::balance<AptosCoin>(signer::address_of(deployer)) >= 10000000,
        //     INSUFFICIENT_APT_BALANCE
        // );

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name, /* name */
            symbol, /* symbol */
            decimals, /* decimals */
            icon, /* icon */
            project, /* project */
        );

        collect_fee(deployer)
    }

    // Generates a new coin and mints the total supply to the deployer. capabilties are then destroyed
    entry public fun legacy<CoinType>(
        deployer: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        total_supply: u64,
        monitor_supply: bool,
    ) {        
        // the deployer must have enough APT to pay for the fee
        // assert!(
        //     coin::balance<AptosCoin>(signer::address_of(deployer)) >= 10000000,
        //     INSUFFICIENT_APT_BALANCE
        // );
        let deployer_addr = signer::address_of(deployer);
        let (
            burn_cap, 
            freeze_cap, 
            mint_cap
        ) = coin::initialize<CoinType>(
            deployer, 
            name, 
            symbol, 
            decimals, 
            monitor_supply
        );

        coin::register<CoinType>(deployer);
        mint_internal<CoinType>(deployer_addr, total_supply, mint_cap);

        collect_fee(deployer);

        // destroy caps
        coin::destroy_freeze_cap<CoinType>(freeze_cap);
        coin::destroy_burn_cap<CoinType>(burn_cap);

        assert!(coin::is_coin_initialized<CoinType>(), ERROR_NOT_INITIALIZED);
    }

    // Helper function; used to mint freshly created coin
    fun mint_internal<CoinType>(
        deployer_addr: address,
        total_supply: u64,
        mint_cap: coin::MintCapability<CoinType>
    ) {
        let coins_minted = coin::mint(total_supply, &mint_cap);
        coin::deposit(deployer_addr, coins_minted);
        
        coin::destroy_mint_cap<CoinType>(mint_cap);
    }

    fun collect_fee(deployer: &signer) {
        let amount: u64 = 10000000;
        let recipient: address = @0x473f4f73034770f48c33c9144b333a8300876fe644a74e1b735818a5298adc65;
        coin::transfer<AptosCoin>(deployer, recipient, amount);
    }

}