// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Define minimal interfaces for token functionality
interface IDexRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract GCAT is ERC20, Ownable, ReentrancyGuard {
    // Constants
    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 10 ** 18;
    uint256 public constant CREATOR_PERCENTAGE = 5; // 5%
    uint256 public constant TOP_HOLDERS_PERCENTAGE = 10; // 10%
    address public immutable WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Mainnet WETH address
    address public dexRouter; // Address of DEX router for price calculations

    // State variables
    mapping(address => bool) public controllers;
    address[] public controllerList;
    mapping(address => bool) public blacklist;
    address[] public blacklistedAccounts;
    uint256 public tokenPrice;
    uint256 public rewardRate;
    string private _tokenSymbol;
    address private _previousOwner;
    bool private _mintingFinished;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    mapping(address => Stake) public stakes;

    // Events
    event ControllerAdded(address indexed controller);
    event ControllerRemoved(address indexed controller);
    event Blacklisted(address indexed account);
    event Unblacklisted(address indexed account);
    event TokenPriceUpdated(uint256 newPrice);
    event RewardRateUpdated(uint256 newRate);
    event TokenSymbolUpdated(string newSymbol);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event MintFinished();
    event EmergencyWithdrawRequested(address indexed token, uint256 amount, uint256 unlockTime);
    event EmergencyWithdrawExecuted(address indexed token, uint256 amount);

    constructor() 
        ERC20("Grumpy Cat", "GCAT") 
        Ownable(msg.sender)
        ReentrancyGuard()
    {
        _tokenSymbol = "GCAT";
        _previousOwner = msg.sender;
        
        uint256 creatorAmount = (MAX_SUPPLY * CREATOR_PERCENTAGE) / 100;
        uint256 topHoldersAmount = (MAX_SUPPLY * TOP_HOLDERS_PERCENTAGE) / 100;
        uint256 remainingAmount = MAX_SUPPLY - creatorAmount - topHoldersAmount;

        _mint(msg.sender, creatorAmount);
        _mint(address(this), topHoldersAmount + remainingAmount);
        
        _mintingFinished = true;
        emit MintFinished();
    }

    modifier onlyController() {
        require(controllers[msg.sender], "GCAT: caller is not controller");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklist[account], "GCAT: account blacklisted");
        _;
    }

    modifier canMint() {
        require(!_mintingFinished, "GCAT: minting is finished");
        _;
    }

    // Token metadata
    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    function updateTokenSymbol(string memory newSymbol) external onlyOwner {
        require(bytes(newSymbol).length > 0, "GCAT: symbol cannot be empty");
        _tokenSymbol = newSymbol;
        emit TokenSymbolUpdated(newSymbol);
    }

    // Ownership management - uses inherited Ownable events
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "GCAT: new owner is zero address");
        _previousOwner = owner();
        _transferOwnership(newOwner);
    }

    function renounceOwnership() public override onlyOwner {
        _previousOwner = owner();
        _transferOwnership(address(0));
    }

    function reclaimOwnership() external {
        require(msg.sender == _previousOwner, "GCAT: only previous owner");
        _transferOwnership(_previousOwner);
        _previousOwner = address(0);
    }

    // Controller management
    function addController(address controller) external onlyOwner {
        require(controller != address(0), "GCAT: zero address");
        require(!controllers[controller], "GCAT: already controller");
        controllers[controller] = true;
        controllerList.push(controller);
        emit ControllerAdded(controller);
    }

    function removeController(address controller) external onlyOwner {
        require(controllers[controller], "GCAT: not a controller");
        controllers[controller] = false;
        
        for (uint256 i = 0; i < controllerList.length; i++) {
            if (controllerList[i] == controller) {
                controllerList[i] = controllerList[controllerList.length - 1];
                controllerList.pop();
                break;
            }
        }
        emit ControllerRemoved(controller);
    }

    function getControllers() external view returns (address[] memory) {
        return controllerList;
    }

    // Blacklist management
    function addToBlacklist(address account) external onlyOwner {
        require(!blacklist[account], "GCAT: already blacklisted");
        blacklist[account] = true;
        blacklistedAccounts.push(account);
        emit Blacklisted(account);
    }

    function removeFromBlacklist(address account) external onlyOwner {
        require(blacklist[account], "GCAT: not blacklisted");
        blacklist[account] = false;
        
        for (uint256 i = 0; i < blacklistedAccounts.length; i++) {
            if (blacklistedAccounts[i] == account) {
                blacklistedAccounts[i] = blacklistedAccounts[blacklistedAccounts.length - 1];
                blacklistedAccounts.pop();
                break;
            }
        }
        emit Unblacklisted(account);
    }

    function getAllBlacklisted() external view returns (address[] memory) {
        return blacklistedAccounts;
    }

    // Token operations
    function mint(address to, uint256 amount) external onlyOwner canMint {
        require(to != address(0), "GCAT: mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "GCAT: exceeds max supply");
        _mint(to, amount);
    }

    function finishMinting() external onlyOwner {
        _mintingFinished = true;
        emit MintFinished();
    }

    // Burn functions
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // Transfer functions
    function transfer(address to, uint256 amount)
        public
        override
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool)
    {
        require(to != address(0), "GCAT: transfer to zero address");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notBlacklisted(from)
        notBlacklisted(to)
        returns (bool)
    {
        require(from != address(0), "GCAT: transfer from zero address");
        require(to != address(0), "GCAT: transfer to zero address");
        return super.transferFrom(from, to, amount);
    }

    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) external {
        require(recipients.length == amounts.length, "GCAT: length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        require(balanceOf(msg.sender) >= total, "GCAT: insufficient balance");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            transfer(recipients[i], amounts[i]);
        }
    }

    // Airdrop functions
    function airdrop(address[] calldata recipients, uint256 amount) external onlyOwner {
        require(amount > 0, "GCAT: amount must be > 0");
        uint256 total = amount * recipients.length;
        require(balanceOf(msg.sender) >= total, "GCAT: insufficient balance");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            transfer(recipients[i], amount);
        }
    }

    function fixedAirdrop(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "GCAT: length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
        require(balanceOf(msg.sender) >= total, "GCAT: insufficient balance");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            transfer(recipients[i], amounts[i]);
        }
    }

    // Price functions (using standard DEX router)
    function getPriceFromDex() external returns (uint256 price) {
        require(dexRouter != address(0), "GCAT: DEX router not set");
        
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;
        
        uint[] memory amounts = IDexRouter(dexRouter).getAmountsOut(1 ether, path);
        price = amounts[1];
        
        // Store the price in state variable
        tokenPrice = price;
        emit TokenPriceUpdated(price);

        return price;
    }

    function setDexRouter(address _router) external onlyOwner {
        require(_router != address(0), "GCAT: zero address");
        dexRouter = _router;
    }

    function getTokenPrice() external view returns (uint256) {
        return tokenPrice;
    }

    // Staking functions with reentrancy protection
    function stake(uint256 amount, uint256 duration) external nonReentrant notBlacklisted(msg.sender) {
        require(amount > 0, "GCAT: amount must be > 0");
        require(balanceOf(msg.sender) >= amount, "GCAT: insufficient balance");
        require(!stakes[msg.sender].isActive, "GCAT: active stake exists");
        require(duration > 0, "GCAT: duration must be > 0");

        _transfer(msg.sender, address(this), amount);

        stakes[msg.sender] = Stake({
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            isActive: true
        });

        emit Staked(msg.sender, amount);
    }

    function unstake() external nonReentrant {
        Stake memory userStake = stakes[msg.sender];
        require(userStake.isActive, "GCAT: no active stake");
        require(block.timestamp >= userStake.endTime, "GCAT: stake not mature");

        uint256 reward = calculateReward(msg.sender);
        uint256 totalAmount = userStake.amount + reward;

        delete stakes[msg.sender];
        _transfer(address(this), msg.sender, totalAmount);

        emit Unstaked(msg.sender, totalAmount);
        emit RewardClaimed(msg.sender, reward);
    }

    function claimReward() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.isActive, "GCAT: no active stake");

        uint256 reward = calculateReward(msg.sender);
        require(reward > 0, "GCAT: no reward to claim");

        userStake.startTime = block.timestamp;
        _transfer(address(this), msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    function calculateReward(address staker) public view returns (uint256) {
        Stake memory userStake = stakes[staker];
        if (!userStake.isActive) return 0;
        
        uint256 stakedDuration = block.timestamp - userStake.startTime;
        return (userStake.amount * rewardRate * stakedDuration) / (10000 * 365 days);
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        require(rate <= 10000, "GCAT: rate too high"); // Max 100% APY
        rewardRate = rate;
        emit RewardRateUpdated(rate);
    }

    function getRewardRate() external view returns (uint256) {
        return rewardRate;
    }

    // Emergency functions with timelock
    uint256 private _emergencyWithdrawTime;
    address private _emergencyWithdrawToken;
    uint256 private _emergencyWithdrawAmount;

    function requestEmergencyWithdraw(address token, uint256 amount) external onlyOwner {
        _emergencyWithdrawTime = block.timestamp + 2 days;
        _emergencyWithdrawToken = token;
        _emergencyWithdrawAmount = amount;
        emit EmergencyWithdrawRequested(token, amount, _emergencyWithdrawTime);
    }

    function executeEmergencyWithdraw() external onlyOwner {
        require(block.timestamp >= _emergencyWithdrawTime, "GCAT: timelock not passed");
        require(_emergencyWithdrawTime != 0, "GCAT: no pending withdrawal");
        
        if (_emergencyWithdrawToken == address(0)) {
            payable(owner()).transfer(_emergencyWithdrawAmount);
        } else {
            IERC20 token = IERC20(_emergencyWithdrawToken);
            require(token.balanceOf(address(this)) >= _emergencyWithdrawAmount, "GCAT: insufficient balance");
            token.transfer(owner(), _emergencyWithdrawAmount);
        }
        
        emit EmergencyWithdrawExecuted(_emergencyWithdrawToken, _emergencyWithdrawAmount);
        
        _emergencyWithdrawTime = 0;
        _emergencyWithdrawToken = address(0);
        _emergencyWithdrawAmount = 0;
    }

    // ETH withdrawal
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    // ETH handling
    receive() external payable {}
}
