module MyModule_addr::Crowdfunding {
    use aptos_framework::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use std::error;
    use std::vector;

    // Error codes
    const E_PROJECT_NOT_FOUND: u64 = 1;
    const E_PROJECT_ALREADY_EXISTS: u64 = 2;
    const E_INSUFFICIENT_FUNDS: u64 = 3;
    const E_PROJECT_ENDED: u64 = 4;
    const E_GOAL_NOT_REACHED: u64 = 5;
    const E_NOT_PROJECT_OWNER: u64 = 6;
    const E_INVALID_AMOUNT: u64 = 7;

    /// Struct representing a contributor's contribution
    struct Contribution has store, drop {
        contributor: address,
        amount: u64,
    }

    /// Struct representing a crowdfunding project
    struct Project has store, key {
        owner: address,
        total_funds: u64,
        goal: u64,
        deadline: u64,  // Unix timestamp
        is_active: bool,
        contributors: vector<Contribution>,
    }

    /// Function to create a new project with a funding goal and deadline
    public fun create_project(
        owner: &signer, 
        goal: u64, 
        duration_seconds: u64
    ) {
        let owner_addr = signer::address_of(owner);
        
        // Ensure project doesn't already exist
        assert!(!exists<Project>(owner_addr), error::already_exists(E_PROJECT_ALREADY_EXISTS));
        
        // Validate inputs
        assert!(goal > 0, error::invalid_argument(E_INVALID_AMOUNT));
        assert!(duration_seconds > 0, error::invalid_argument(E_INVALID_AMOUNT));

        let current_time = timestamp::now_seconds();
        let deadline = current_time + duration_seconds;

        let project = Project {
            owner: owner_addr,
            total_funds: 0,
            goal,
            deadline,
            is_active: true,
            contributors: vector::empty<Contribution>(),
        };

        move_to(owner, project);
    }

    /// Function for users to contribute to a project
    public fun contribute_to_project(
        contributor: &signer, 
        project_owner: address, 
        amount: u64
    ) acquires Project {
        // Validate inputs
        assert!(amount > 0, error::invalid_argument(E_INVALID_AMOUNT));
        assert!(exists<Project>(project_owner), error::not_found(E_PROJECT_NOT_FOUND));

        let project = borrow_global_mut<Project>(project_owner);
        let contributor_addr = signer::address_of(contributor);
        let current_time = timestamp::now_seconds();

        // Check if project is still active and within deadline
        assert!(project.is_active, error::invalid_state(E_PROJECT_ENDED));
        assert!(current_time <= project.deadline, error::invalid_state(E_PROJECT_ENDED));

        // Check if contributor has sufficient balance
        assert!(coin::balance<AptosCoin>(contributor_addr) >= amount, 
                error::invalid_argument(E_INSUFFICIENT_FUNDS));

        // Transfer the contribution
        let contribution = coin::withdraw<AptosCoin>(contributor, amount);
        coin::deposit<AptosCoin>(project_owner, contribution);

        // Update project state
        project.total_funds = project.total_funds + amount;
        
        // Record the contribution
        let contrib = Contribution {
            contributor: contributor_addr,
            amount,
        };
        vector::push_back(&mut project.contributors, contrib);
    }

    /// Function to withdraw funds when goal is reached
    public fun withdraw_funds(owner: &signer) acquires Project {
        let owner_addr = signer::address_of(owner);
        assert!(exists<Project>(owner_addr), error::not_found(E_PROJECT_NOT_FOUND));

        let project = borrow_global_mut<Project>(owner_addr);
        
        // Only project owner can withdraw
        assert!(project.owner == owner_addr, error::permission_denied(E_NOT_PROJECT_OWNER));
        
        // Check if goal is reached
        assert!(project.total_funds >= project.goal, error::invalid_state(E_GOAL_NOT_REACHED));
        
        // Check if project is still active
        assert!(project.is_active, error::invalid_state(E_PROJECT_ENDED));

        let withdrawal_amount = project.total_funds;
        project.total_funds = 0;
        project.is_active = false;
    }

    /// Function to end project (can be called after deadline or by owner)
    public fun end_project(caller: &signer, project_owner: address) acquires Project {
        assert!(exists<Project>(project_owner), error::not_found(E_PROJECT_NOT_FOUND));
        
        let project = borrow_global_mut<Project>(project_owner);
        let caller_addr = signer::address_of(caller);
        let current_time = timestamp::now_seconds();

        // Either project owner can end it, or anyone can end it after deadline
        assert!(
            caller_addr == project.owner || current_time > project.deadline,
            error::permission_denied(E_NOT_PROJECT_OWNER)
        );

        project.is_active = false;
    }

    /// View function to get project details
    #[view]
    public fun get_project_info(project_owner: address): (u64, u64, u64, bool, u64) acquires Project {
        assert!(exists<Project>(project_owner), error::not_found(E_PROJECT_NOT_FOUND));
        
        let project = borrow_global<Project>(project_owner);
        (
            project.total_funds,
            project.goal,
            project.deadline,
            project.is_active,
            vector::length(&project.contributors)
        )
    }

    /// View function to check if goal is reached
    #[view]
    public fun is_goal_reached(project_owner: address): bool acquires Project {
        assert!(exists<Project>(project_owner), error::not_found(E_PROJECT_NOT_FOUND));
        
        let project = borrow_global<Project>(project_owner);
        project.total_funds >= project.goal
    }

    /// View function to get contribution by contributor
    #[view]
    public fun get_contributor_amount(project_owner: address, contributor: address): u64 acquires Project {
        assert!(exists<Project>(project_owner), error::not_found(E_PROJECT_NOT_FOUND));
        
        let project = borrow_global<Project>(project_owner);
        let contributors = &project.contributors;
        let len = vector::length(contributors);
        let i = 0;
        let total_contribution = 0;

        while (i < len) {
            let contrib = vector::borrow(contributors, i);
            if (contrib.contributor == contributor) {
                total_contribution = total_contribution + contrib.amount;
            };
            i = i + 1;
        };

        total_contribution
    }

    /// Test helper function to check if project exists
    #[view]
    public fun project_exists(project_owner: address): bool {
        exists<Project>(project_owner)
    }
}