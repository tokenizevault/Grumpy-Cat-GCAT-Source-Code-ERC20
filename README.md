// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; 

contract GrumpyCat is ERC20 {
    // Contract owner
    address public owner;
    
    // Mapping of controllers
    mapping(address => bool) public controllers;
    
    // Mapping of blacklisted accounts
    mapping(address => bool) public blacklist;
    
    // Flag indicating whether the contract is paused
    bool public paused;

    // Constructor
    constructor() ERC20("Grumpy Cat", "GCAT") {
        _mint(msg.sender, 100000000000 * 10 ** 18);
        owner = msg.sender;
        paused = false;
    }

    // Modifier: Only owner can execute
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    // Modifier: Only controllers can execute
    modifier onlyController() {
        require(controllers[msg.sender], "Only controllers can call this function");
        _;
    }

    // Modifier: When not paused
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    // Get owner address
    function getOwner() public view returns (address) {
        return owner;
    }

    // Check if caller is owner
    function _checkOwnership() internal view returns (bool) {
        return msg.sender == owner;
    }

    // Transfer ownership to a new address
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid Address");
        owner = _newOwner;
    }

    // Renounce ownership
    function renounceOwnership() external onlyOwner {
        owner = address(0);
    }

    // Add controller
    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
    }

    // Remove controller
    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
    }

    // Pause contract
    function pause() external onlyOwner {
        paused = true;
    }

    // Unpause contract
    function unpause() external onlyOwner {
        paused = false;
    }

    // Get balance of an account
    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }

    // Mint new tokens
    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    }

    // Burn tokens
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // Burn tokens from a specified account
    function burnFrom(address from, uint256 value) external whenNotPaused returns (bool) {
        _burn(from, value);
        return true;
    }

    // Transfer tokens
    function transfer(address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!_checkBlacklist(msg.sender), "Sender is blacklisted");
        require(!_checkBlacklist(to), "Recipient is blacklisted");
        return super.transfer(to, value);
    }

    // Transfer tokens from one account to another
    function transferFrom(address from, address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!_checkBlacklist(from), "Sender is blacklisted");
        require(!_checkBlacklist(to), "Recipient is blacklisted");
        return super.transferFrom(from, to, value);
    }

    // Approve spending limit for an address
    function approve(address spender, uint256 value) public override whenNotPaused returns (bool) {
        return super.approve(spender, value);
    }

    // Increase spending limit for an address
    function increaseAllowance(address spender, uint256 addedValue) public whenNotPaused returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    // Decrease spending limit for an address
    function decreaseAllowance(address spender, uint256 subtractedValue) public whenNotPaused returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "Decreased allowance below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    // Add an account to the blacklist
    function addToBlacklist(address account) external onlyOwner {
        blacklist[account] = true;
    }

    // Remove an account from the blacklist
    function removeFromBlacklist(address account) external onlyOwner {
        blacklist[account] = false;
    }

    // Check if an account is blacklisted
    function isBlacklisted(address account) public view returns (bool) {
        return blacklist[account];
    }

    // Internal function to check if an account is blacklisted
    function _checkBlacklist(address account) internal view returns (bool) {
        return blacklist[account];
    }
}
