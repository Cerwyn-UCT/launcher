/*
    Tool for deploying coins.
    - Capabilities are destroyed after the coin is created (will add a way to keep them if needed)
    - The deployer is initialized with a fee that is paid in APT
    - The deployer is initialized with an owner address that can change the fee and owner address
    - The deployer is initialized with a coins table that maps coin addresses to their addresses
    - coins can be added/removed to the map manually by the deployer owner
    - can view the coins table
*/

module launch::deployers {

    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_std::type_info;
    use std::signer;
    use std::string::{String};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object, ConstructorRef, DeriveRef};
    use std::option;
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};

    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    struct Config has key {
        owner: address,
        fee: u64
    }

    #[event]
    struct NewFeeEvent has drop, store { new_fee: u64 }
    fun emit_new_fee_event(new_fee: u64) {
        event::emit<NewFeeEvent>(NewFeeEvent { new_fee })
    }

    #[event]
    struct NewOwnerEvent has drop, store { new_owner: address }
    fun emit_new_owner_event(new_owner: address) {
        event::emit<NewOwnerEvent>(NewOwnerEvent { new_owner })
    }

    // Error Codes 
    const ERROR_INVALID_BAPT_ACCOUNT: u64 = 0;
    const ERROR_ERROR_INSUFFICIENT_APT_BALANCE: u64 = 1;
    const INSUFFICIENT_APT_BALANCE: u64 = 2;
    const ERROR_NOT_INITIALIZED: u64 = 3;


    entry public fun init(launch_framework: &signer, fee: u64, owner: address){
        assert!(signer::address_of(launch_framework) == @launch, ERROR_INVALID_BAPT_ACCOUNT);
        move_to(launch_framework, Config { owner, fee })
    }

    entry public fun update_fee(launch_framework: &signer, new_fee: u64) acquires Config {
        assert!(
            signer::address_of(launch_framework) == @launch, 
            ERROR_INVALID_BAPT_ACCOUNT
        );
        // only allowed after the deployer is initialized
        assert!(exists<Config>(@launch), ERROR_INVALID_BAPT_ACCOUNT);

        let config = borrow_global_mut<Config>(@launch);
        config.fee = new_fee;
        emit_new_fee_event(new_fee);
    }

    entry public fun update_owner(launch_framework: &signer, new_owner: address) acquires Config {
        assert!(
            signer::address_of(launch_framework) == @launch, 
            ERROR_INVALID_BAPT_ACCOUNT
        );
        // only allowed after the deployer is initialized
        assert!(exists<Config>(@launch), ERROR_INVALID_BAPT_ACCOUNT);

        let config = borrow_global_mut<Config>(@launch);
        config.owner = new_owner;
        emit_new_owner_event(new_owner);
    }

    public fun generate_coin_v2<CoinType>(
        constructor_ref: &ConstructorRef,
        name: String,
        symbol: String,
        icon: String,
        project: String,
        decimals: u8,
        total_supply: u64,
        monitor_supply: bool,
    )  {        
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name, /* name */
            symbol, /* symbol */
            decimals, /* decimals */
            icon, /* icon */
            project, /* project */
        );

        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
        )

        // Do the fee
    }
    public fun generate_coin_v3(
        constructor_ref: &ConstructorRef,
        name: String,
        symbol: String,
        icon: String,
        project: String,
        decimals: u8,
        total_supply: u64,
        monitor_supply: bool,
    )  {        
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            name, /* name */
            symbol, /* symbol */
            decimals, /* decimals */
            icon, /* icon */
            project, /* project */
        );

        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
        )

        // Do the fee
    }

    // Generates a new coin and mints the total supply to the deployer. capabilties are then destroyed
    entry public fun generate_coin<CoinType>(
        deployer: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        total_supply: u64,
        monitor_supply: bool,
    ) acquires Config {        
        // only allowed after the deployer is initialized
        assert!(exists<Config>(@launch), ERROR_INVALID_BAPT_ACCOUNT);
        // the deployer must have enough APT to pay for the fee
        assert!(
            coin::balance<AptosCoin>(signer::address_of(deployer)) >= borrow_global<Config>(@launch).fee,
            INSUFFICIENT_APT_BALANCE
        );
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

    // checks if a given owner address + coin_type exists in coin_table; callable only by anyone
    public fun is_coin_owner<CoinType>(sender: &signer): bool {
        let sender_addr = signer::address_of(sender);
        if (owner_address<CoinType>() == sender_addr) 
        { true } else false
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

    fun collect_fee(deployer: &signer) acquires Config {
        let config = borrow_global_mut<Config>(@launch);
        coin::transfer<AptosCoin>(deployer, config.owner, config.fee);
    }

    #[view]
    public fun owner_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    #[test_only]
    use aptos_framework::aptos_coin;
    #[test_only]
    struct FakeBAPT {}
    #[test_only]
    struct FakeUSDC {}
    #[test_only]
    use std::string;

    #[test_only]
    public fun init_test(launch_framework: &signer, fee: u64, owner: address) {
        assert!(
            signer::address_of(launch_framework) == @launch, 
            ERROR_INVALID_BAPT_ACCOUNT
        );

        move_to(launch_framework, Config { owner, fee });
    }

    #[test(aptos_framework = @0x1, launch_framework = @launch, user = @0x123)]
    // #[expected_failure, code = 65537]
    fun test_user_deploys_coin(
        aptos_framework: signer,
        launch_framework: signer,
        user: &signer,
    ) acquires Config {
        aptos_framework::account::create_account_for_test(signer::address_of(&launch_framework));
        // aptos_framework::account::create_account_for_test(signer::address_of(user));
        init(&launch_framework, 1, signer::address_of(&launch_framework));
        // register aptos coin and mint some APT to be able to pay for the fee of generate_coin
        coin::register<AptosCoin>(&launch_framework);
        let (aptos_coin_burn_cap, aptos_coin_mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
        // mint some APT to be able to pay for the fee of generate_coin
        aptos_coin::mint(&aptos_framework, signer::address_of(&launch_framework), 1000);
        
        generate_coin<FakeBAPT>(
            &launch_framework,
            string::utf8(b"Fake BAPT"),
            string::utf8(b"BAPT"),
            4,
            1000000,
            true,
        );

        // destroy APT mint and burn caps
        coin::destroy_mint_cap<AptosCoin>(aptos_coin_mint_cap);
        coin::destroy_burn_cap<AptosCoin>(aptos_coin_burn_cap);

        // assert FakeBAPT is generated and supply is moved under the deployer's wallet
        assert!(coin::balance<FakeBAPT>(signer::address_of(&launch_framework)) == 1000000, 1);

        // assert coins table contains the newly created coin
        let config = borrow_global<Config>(@launch);
        let coin_address = owner_address<FakeBAPT>();
        assert!(is_coin_owner<FakeBAPT>(&launch_framework), 1);
    }
}