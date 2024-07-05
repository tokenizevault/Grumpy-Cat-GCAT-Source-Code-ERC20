// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract GCAT is ERC20 {

    address public owner;
    address private _previousOwner;
    mapping(address => bool) public controllers;
    mapping(address => bool) public blacklist;
    bool public paused;
    mapping(address => uint256[]) private _balancesHistory;
    mapping(address => Stake) public stakes;
    mapping(address => Lock[]) private locks; // Added Lock mapping

    IPoolManager public poolManager;
    uint24 private constant FEE = 3000; // Uniswap V4 default fee

    // Mapping for pools
    mapping(uint256 => PoolState) public pools;
    uint256 public nextPoolId = 1;

    struct Lock {
        uint256 amount;
        uint256 unlockTime;
    }

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    enum PoolState { Inactive, Active, Closed }

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    uint256 public tokenPrice; // Added tokenPrice variable
    uint256 public rewardRate; // Added rewardRate variable
    address public reserveFundAddress; // Added reserveFundAddress variable

    constructor() ERC20("Grumpy Cat", "GCAT") {
        _mint(msg.sender, 100000000000 * 10 ** 18);
        owner = msg.sender;
        paused = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call");
        _;
    }

    modifier onlyController() {
        require(controllers[msg.sender], "Only controllers can call");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    function _checkOwnership() internal view returns (bool) {
        return msg.sender == owner;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        _previousOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(_previousOwner, _newOwner);
    }

    function renounceOwnership() external onlyOwner {
        _previousOwner = owner;
        owner = address(0);
        emit OwnershipTransferred(_previousOwner, address(0));
    }

    function reclaimOwnership() public {
        require(msg.sender == _previousOwner, "Only previous owner can reclaim");
        emit OwnershipTransferred(address(0), _previousOwner);
        owner = _previousOwner;
        _previousOwner = address(0); // Clear previous owner
    }

    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
    }

    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function mint(address to, uint256 value) external onlyOwner {
        _mint(to, value);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function burnFrom(address from, uint256 value) external whenNotPaused returns (bool) {
        _burn(from, value);
        return true;
    }

    function transfer(address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!_checkBlacklist(msg.sender), "Sender is blacklisted");
        require(!_checkBlacklist(to), "Recipient is blacklisted");
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override whenNotPaused returns (bool) {
        require(!_checkBlacklist(from), "Sender is blacklisted");
        require(!_checkBlacklist(to), "Recipient is blacklisted");
        return super.transferFrom(from, to, value);
    }

    function approve(address spender, uint256 value) public override whenNotPaused returns (bool) {
        return super.approve(spender, value);
    }

    function increaseAllowance(address spender, uint256 addedValue) public whenNotPaused returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public whenNotPaused returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "Decreased allowance below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    function addToBlacklist(address account) external onlyOwner {
        blacklist[account] = true;
    }

    function removeFromBlacklist(address account) external onlyOwner {
        blacklist[account] = false;
    }

    function isBlacklisted(address account) public view returns (bool) {
        return blacklist[account];
    }

    function _checkBlacklist(address account) internal view returns (bool) {
        return blacklist[account];
    }

    function balanceOfAt(address account, uint256 index) public view returns (uint256) {
        require(index < _balancesHistory[account].length, "Invalid index");
        return _balancesHistory[account][index];
    }

    function balanceHistoryLength(address account) public view returns (uint256) {
        return _balancesHistory[account].length;
    }

    function snapshot() public onlyOwner {
        uint256 currentBlock = block.number;
        for (uint256 i = 0; i < super.totalSupply(); i++) {
            _balancesHistory[msg.sender].push(currentBlock);
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
    }

    function allowanceOf(address _owner, address spender) public view returns (uint256) {
        return super.allowance(_owner, spender);
    }

    function airdrop(address[] memory recipients, uint256[] memory amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(owner, recipients[i], amounts[i]);
        }
    }

    // Freeze account
    function freezeAccount(address account) public onlyOwner {
        require(account != address(0), "Invalid address");
        require(!blacklist[account], "Account is blacklisted");
        blacklist[account] = true;
    }

    // Unfreeze account
    function unfreezeAccount(address account) public onlyOwner {
        require(account != address(0), "Invalid address");
        require(blacklist[account], "Account is not blacklisted");
        blacklist[account] = false;
    }

    // Lock tokens for a period
    function lockTokens(address account, uint256 amount, uint256 time) public onlyOwner {
        require(account != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(account) >= amount, "Insufficient balance");
        Lock memory newLock = Lock({
            amount: amount,
            unlockTime: block.timestamp + time
        });
        locks[account].push(newLock);
        _transfer(account, address(this), amount); // Transfer tokens to contract for locking
    }

    // Unlock tokens
    function unlockTokens(address account, uint256 amount) public onlyOwner {
        require(account != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than 0");
        uint256 unlockableAmount = 0;
        for (uint256 i = 0; i < locks[account].length; i++) {
            if (block.timestamp >= locks[account][i].unlockTime) {
                unlockableAmount += locks[account][i].amount;
                delete locks[account][i]; // Remove the unlocked lock
            }
        }

        require(unlockableAmount >= amount, "Not enough unlockable tokens");
        _transfer(address(this), account, amount); // Transfer tokens back to the account
    }

    // Emergency withdrawal function
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        _transfer(owner, to, amount);
    }

    // Increase total supply
    function increaseTotalSupply(uint256 amount) external onlyOwner {
        _mint(owner, amount);
    }

    // Decrease total supply
    function decreaseTotalSupply(uint256 amount) external onlyOwner {
        _burn(owner, amount);
    }

    // Withdraw ETH from contract
    function withdrawETH(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(owner).transfer(amount);
    }

    // Receive ETH
    receive() external payable {
        // Address can receive ETH
    }

    // Fallback function
    fallback() external payable {
        // Address can fallback
    }

    // Transfer tokens in batch
    function batchTransfer(address[] memory recipients, uint256[] memory amounts) external whenNotPaused {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
    }

    // Freeze and lock tokens in one function
    function freezeAndLock(address account, uint256 amount, uint256 time) external onlyOwner {
        freezeAccount(account);
        lockTokens(account, amount, time);
    }

    // Unfreeze and unlock tokens in one function
    function unfreezeAndUnlock(address account, uint256 amount) external onlyOwner {
        unfreezeAccount(account);
        unlockTokens(account, amount);
    }

    // Enable trading
    function enableTrading() external onlyOwner {
        paused = false;
    }

    // Disable trading
    function disableTrading() external onlyOwner {
        paused = true;
    }

    // Set token price
    function setTokenPrice(uint256 price) external onlyOwner {
        tokenPrice = price;
    }

    // Get token price
    function getTokenPrice() public view returns (uint256) {
        return tokenPrice;
    }

    // Function to buy tokens
    function buyToken() public payable whenNotPaused {
        // Calculate the number of tokens to be bought
        uint256 tokens = msg.value / tokenPrice;
        // Transfer the tokens to the buyer
        require(transfer(msg.sender, tokens), "Token transfer failed");
        // Transfer the received Ether to the wallet
        payable(owner).transfer(msg.value);
    }

    // Function to sell tokens
    function sellToken(uint256 tokenAmount) public whenNotPaused {
        // Calculate the amount of Ether to be paid
        uint256 etherAmount = tokenAmount * tokenPrice;
        // Ensure the contract has enough Ether to pay
        require(address(this).balance >= etherAmount, "Not enough Ether in the contract");
        // Transfer the tokens from the seller to the contract
        require(transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        // Transfer the Ether to the seller
        (bool success, ) = msg.sender.call{value: etherAmount}("");
        require(success, "Ether transfer failed");
    }

    // Airdrop specific amount to multiple accounts
    function airdropFixedAmount(address[] memory recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(owner, recipients[i], amount);
        }
    }

    // Function to add liquidity to Uniswap V4
    function addLiquidity(uint256 amountToken, uint256 amountETH) external onlyOwner {
        _approve(address(this), address(poolManager), amountToken);
        poolManager.addLiquidity{ value: amountETH }(
            address(this),
            amountToken,
            0, // amountTokenMin
            0, // amountETHMin
            owner,
            block.timestamp + 3600
        );
    }

    // Function to swap tokens for ETH using Uniswap V4
    function swapTokenForETH(uint256 amount) external onlyOwner {
        _approve(address(this), address(poolManager), amount);
        poolManager.swapExactTokensForETH(
            amount,
            0, // amountOutMin
            FEE, // fee
            owner,
            block.timestamp + 3600
        );
    }

    // Function to swap ETH for tokens using Uniswap V4
    function swapETHForToken(uint256 amount) external onlyOwner payable {
        poolManager.swapExactETHForTokens{ value: amount }(
            0, // amountOutMin
            address(this),
            owner,
            block.timestamp + 3600
        );
    }

    // Function to remove liquidity from Uniswap V4
    function removeLiquidity(uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) external onlyOwner {
        poolManager.removeLiquidity(
            address(this),
            address(0), // Changed from ETH to address(0)
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // Function to stake tokens
    function stakeTokens(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        // Transfer tokens from user to contract
        _transfer(msg.sender, address(this), amount);
        // Update stake information
        if (stakes[msg.sender].isActive) {
            stakes[msg.sender].amount += amount;
        } else {
            stakes[msg.sender] = Stake({
                amount: amount,
                startTime: block.timestamp,
                endTime: 0,
                isActive: true
            });
        }
        emit Staked(msg.sender, amount);
    }

    // Function to unstake tokens
    function unstakeTokens(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(stakes[msg.sender].isActive, "No active stake found");
        require(stakes[msg.sender].amount >= amount, "Insufficient staked amount");
        // Calculate and transfer staked tokens back to user
        uint256 stakedAmount = stakes[msg.sender].amount;
        _transfer(address(this), msg.sender, amount);
        // Update stake information
        stakes[msg.sender].amount -= amount;
        if (stakes[msg.sender].amount == 0) {
            stakes[msg.sender].isActive = false;
        }
        emit Unstaked(msg.sender, amount);
    }

    // Function to claim staking rewards
    function claimRewards() external {
        require(stakes[msg.sender].isActive, "No active stake found");
        // Calculate rewards (for demonstration, use a simple rate)
        uint256 reward = (block.timestamp - stakes[msg.sender].startTime) * rewardRate;
        require(reward > 0, "No rewards available");
        // Transfer rewards to user
        _transfer(address(this), msg.sender, reward);
        // Update stake information
        stakes[msg.sender].startTime = block.timestamp;
        emit RewardClaimed(msg.sender, reward);
    }

    // Function to set the reward rate for staking
    function setRewardRate(uint256 rate) external onlyOwner {
        rewardRate = rate;
    }

    // Function to get the current reward rate for staking
    function getRewardRate() external view returns (uint256) {
        return rewardRate;
    }

    // Function to set the reserve fund address
    function setReserveFundAddress(address _reserveFundAddress) external onlyOwner {
        reserveFundAddress = _reserveFundAddress;
    }

    // Function to get the reserve fund address
    function getReserveFundAddress() external view returns (address) {
        return reserveFundAddress;
    }

    // Function to deposit a specified amount to the reserve fund account
    function depositToReserveFund(uint256 amount) external {
        // Grumpy Cat Reserve Fund
    }

    // Function for the owner to withdraw from the reserve fund account
    function withdrawFromReserveFund(uint256 amount) external onlyOwner {
        // Grumpy Cat Reserve Fund
    }
}
