
// SPDX-License-Identifier: Unlicensed
 
pragma solidity ^0.8.5;


library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
}

/**
 * BEP20 standard interface.
 */
interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * Allows for contract ownership along with multi-address authorization
 */
abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    /**
     * Function modifier to require caller to be contract owner
     */
    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    /**
     * Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    /**
     * Authorize address. Owner only
     */
    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    /**
     * Remove address' authorization. Owner only
     */
    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    /**
     * Check if address is owner
     */
    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    /**
     * Return address' authorization status
     */
    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    /**
     * Transfer ownership to new address. Caller must be owner. Leaves old owner authorized
     */
    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
   struct TokenInput {
    address token;
    uint amount;
}

struct SwapStep {
    address pool; // The pool of the step.
    bytes data; // The data to execute swap with the pool.
    address callback;
    bytes callbackData;
}

struct SwapPath {
    SwapStep[] steps; // Steps of the path.
    address tokenIn; // The input token of the path.
    uint amountIn; // The input token amount of the path.
}

struct SplitPermitParams {
    address token;
    uint approveAmount;
    uint deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct ArrayPermitParams {
    uint approveAmount;
    uint deadline;
    bytes signature;
}

// Returns the vault address.
function vault() external view returns (address);

// Returns the wETH address.
function wETH() external view returns (address);

// Adds some liquidity (supports unbalanced mint).
// Alternatively, use `addLiquidity2` with the same params to register the position,
// to make sure it can be indexed by the interface.


// Performs a swap.
function swap(
    SwapPath[] memory paths,
    uint amountOutMin,
    uint deadline
) external payable returns (uint amountOut);

function swapWithPermit(
    SwapPath[] memory paths,
    uint amountOutMin,
    uint deadline,
    SplitPermitParams calldata permit
) external payable returns (uint amountOut);

/// @notice Wrapper function to allow pool deployment to be batched.
function createPool(address factory, bytes calldata data) external payable returns (address);
}

interface IDividendDistributor {
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external;
    function setShare(address shareholder, uint256 amount) external;
    function deposit() external payable;
    function process(uint256 gas) external;
}

contract DividendDistributor is IDividendDistributor {
    using SafeMath for uint256;

    address _token;
    address admin;
    address pair = 0x80115c708E12eDd42E504c1cD52Aea96C547c05c; //USDC-WETH Pair

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IBEP20 USDC = IBEP20(0x3355df6D4c9C3035724Fd0e3914dE96A5a83aaf4); 
    
    IDEXRouter router;

    address[] shareholders;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;

    mapping (address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 30 * 60;
    uint256 public minDistribution = 1 * (10 ** 6);

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }
    modifier onlyAdmin() {
        require(msg.sender == admin); _;
    }

    constructor (address _router, address _admin) {
        router = _router != address(0)
            ? IDEXRouter(_router)
            : IDEXRouter(0x2da10A1e27bF85cEdD8FFb1AbBe97e53391C0295);
        _token = msg.sender;
        admin = _admin;
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit() external payable override onlyToken {
        uint256 balanceBefore = USDC.balanceOf(address(this));



            
    IDEXRouter.SwapStep[] memory swap_steps = new IDEXRouter.SwapStep[](1);
    swap_steps[0] = IDEXRouter.SwapStep(pair, abi.encode(router.wETH(), address(this), 1), address(0), new bytes(0));
    IDEXRouter.SwapPath[] memory paths = new IDEXRouter.SwapPath[](1);
    paths[0] = IDEXRouter.SwapPath(swap_steps, 0x0000000000000000000000000000000000000000, msg.value);

    router.swap(paths, 0, block.timestamp + 1800);




        uint256 amount = USDC.balanceOf(address(this)).sub(balanceBefore);

        totalDividends = totalDividends.add(amount);
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalShares));
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while(gasUsed < gas && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }

            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }
    
    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
                && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0){
            totalDistributed = totalDistributed.add(amount);
            USDC.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }
    
    function claimDividend(address shareholder) external onlyToken{
        distributeDividend(shareholder);
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }
    function clearStuck(address _stuckAddress, address _ownerOfTokens, uint256 _amount) public onlyAdmin {
         IBEP20 StuckToken = IBEP20(_stuckAddress);
         StuckToken.transfer(_ownerOfTokens, _amount);

    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }
    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
}

contract zkNEET is IBEP20, Auth {
    using SafeMath for uint256;

    address USDC = 0x3355df6D4c9C3035724Fd0e3914dE96A5a83aaf4;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address private vault = 0x621425a1Ef6abE91058E9712575dcc4258F8d091;

    string constant _name = "zkNEET";
    string constant _symbol = "zkNEET";
    uint8 constant _decimals = 18;

    uint256 _totalSupply = 1 * 10**9 * (10 ** _decimals);

    uint256 public _maxTxAmount = _totalSupply * 2 / 100; // 2%
    
    uint256 public _maxWalletToken = ( _totalSupply * 5 ) / 100; // 5%


    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isTimelockExempt;
    mapping (address => bool) isDividendExempt;


    
    uint256 reflectionFee = 500;
    uint256 marketingFee = 300;
    uint256 totalFee = 800;
    uint256 feeDenominator = 10000;

    address public marketingFeeReceiver;

    IDEXRouter public router;
    address public pair;

    uint256 public launchedAt;
     bool public tradingOpen = false;

    DividendDistributor distributor;
    uint256 distributorGas = 500000;

    // Cooldown & timer functionality
    bool public buyCooldownEnabled = true;
    uint8 public cooldownTimerInterval = 10;
    mapping (address => uint) private cooldownTimer;

    bool public swapEnabled = true;
    uint256 public swapThreshold = _totalSupply / 100; // 1% of supply
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () Auth(msg.sender) {
        router = IDEXRouter(0x2da10A1e27bF85cEdD8FFb1AbBe97e53391C0295);
        // pair = IDEXFactory(router.factory()).createPair(MTS, address(this)); 
        _allowances[address(this)][address(router)] = type(uint256).max;

        distributor = new DividendDistributor(address(router), msg.sender);
        
        address _presaler = 0x0f9C07A1BbcE364444c0de1839C473CA48D1384E;
        isFeeExempt[_presaler] = true;
        isTxLimitExempt[_presaler] = true; 
        
        // No timelock for these people
        isTimelockExempt[msg.sender] = true;
        isTimelockExempt[DEAD] = true;
        isTimelockExempt[address(this)] = true;
        
        
        isDividendExempt[address(this)] = true;
        isDividendExempt[vault] = true;
        isDividendExempt[DEAD] = true;

        marketingFeeReceiver = 0x0f9C07A1BbcE364444c0de1839C473CA48D1384E;

        _balances[_presaler] = _totalSupply;
        emit Transfer(address(0), _presaler, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function getDistributor() public view returns (address) {
        return address(distributor);
    }
      function clearStuckTokens(address _stuckAddress, address _ownerOfTokens, uint256 _amount) public onlyOwner {
         IBEP20 StuckToken = IBEP20(_stuckAddress);
         StuckToken.transfer(_ownerOfTokens, _amount);
    }
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    //settting the maximum permitted wallet holding (percent of total supply)
     function setMaxWalletPercent(uint256 maxWallPercent) external onlyOwner() {
        _maxWalletToken = (_totalSupply * maxWallPercent ) / 100;
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        if(!authorizations[sender] && !authorizations[recipient]){
            require(tradingOpen,"Trading not open yet");
        }

        // max wallet code
        if (!authorizations[sender] && recipient != address(this)  && recipient != address(DEAD) && recipient != vault && recipient != marketingFeeReceiver){
            uint256 heldTokens = balanceOf(recipient);
            require((heldTokens + amount) <= _maxWalletToken,"Total Holding is currently limited, you can not buy that much.");}
        

        
        // cooldown timer, so a bot doesnt do quick trades! 1min gap between 2 trades.
        if (sender == vault &&
            buyCooldownEnabled &&
            !isTimelockExempt[recipient]) {
            require(cooldownTimer[recipient] < block.timestamp,"Please wait for 1min between two buys");
            cooldownTimer[recipient] = block.timestamp + cooldownTimerInterval;
        }


        // Checks max transaction limit
        checkTxLimit(sender, amount);

        
        if(shouldSwapBack()){ swapBack(); }

        //Exchange tokens
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, amount) : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);

        // Dividend tracker
        if(!isDividendExempt[sender]) {
            try distributor.setShare(sender, _balances[sender]) {} catch {}
        }

        if(!isDividendExempt[recipient]) {
            try distributor.setShare(recipient, _balances[recipient]) {} catch {} 
        }

        try distributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
 
    
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function checkTxLimit(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount.mul(totalFee).div(feeDenominator);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != vault
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= swapThreshold;
    }

    // switch Trading
    function tradingStatus(bool _status) public onlyOwner {
        tradingOpen = _status;
    }

    // enable cooldown between trades
    function cooldownEnabled(bool _status, uint8 _interval) public onlyOwner {
        buyCooldownEnabled = _status;
        cooldownTimerInterval = _interval;
    }
function swapTokensForEth(uint256 tokenAmount) private swapping {
         approve(0x2da10A1e27bF85cEdD8FFb1AbBe97e53391C0295, tokenAmount);
    
    IDEXRouter.SwapStep[] memory swap_steps = new IDEXRouter.SwapStep[](1);
    swap_steps[0] = IDEXRouter.SwapStep(pair, abi.encode(address(this), address(this), 1), address(0), new bytes(0));
    IDEXRouter.SwapPath[] memory paths = new IDEXRouter.SwapPath[](1);
    paths[0] = IDEXRouter.SwapPath(swap_steps, address(this), tokenAmount);

    router.swap(paths, 0, block.timestamp + 1800);
    }

    function swapBack() internal swapping {
        
        uint256 amountToSwap = swapThreshold;

       

        uint256 balanceBefore = address(this).balance;
        swapTokensForEth(amountToSwap);

        uint256 amountETH = address(this).balance.sub(balanceBefore);

        uint256 totalETHFee = totalFee;
        uint256 amountETHReflection = amountETH.mul(reflectionFee).div(totalETHFee);
        uint256 amountETHMarketing = amountETH.mul(marketingFee).div(totalETHFee);

        try distributor.deposit{value: amountETHReflection}() {} catch {}
        (bool success,) = payable(marketingFeeReceiver).call{value: amountETHMarketing}("");
        require(success, "receiver rejected ETH transfer");
    }
  
    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch() internal {
        launchedAt = block.number;
    }

    function setTxLimit(uint256 amount) external authorized {
        require(amount >= _totalSupply / 1000);
        _maxTxAmount = amount;
    }

    function setIsDividendExempt(address holder, bool exempt) external authorized {
        require(holder != address(this) && holder != vault);
        isDividendExempt[holder] = exempt;
        if(exempt){
            distributor.setShare(holder, 0);
        }else{
            distributor.setShare(holder, _balances[holder]);
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external authorized {
        isFeeExempt[holder] = exempt;
    }

    function setIsTxLimitExempt(address holder, bool exempt) external authorized {
        isTxLimitExempt[holder] = exempt;
    }

    function setIsTimelockExempt(address holder, bool exempt) external authorized {
        isTimelockExempt[holder] = exempt;
    }

    function setFees( uint256 _reflectionFee, uint256 _marketingFee, uint256 _feeDenominator) external authorized {
        reflectionFee = _reflectionFee;
        marketingFee = _marketingFee;
        totalFee = _reflectionFee.add(_marketingFee);
        feeDenominator = _feeDenominator;
    }

    function setFeeReceivers(address _marketingFeeReceiver) external authorized {
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount) external authorized {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

   function manualSend() external authorized {
        uint256 contractETHBalance = address(this).balance;
        (bool success, ) = payable(marketingFeeReceiver).call{value: contractETHBalance}("");
        require(success, "Transfer failed.");
    }
    
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external authorized {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution);
    }
    
    function claimDividend() external {
        distributor.claimDividend(msg.sender);
    }
    
    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        return distributor.getUnpaidEarnings(shareholder);
    } 

    function setDistributorSettings(uint256 gas) external authorized {
        require(gas < 750000);
        distributorGas = gas;
    }
    
    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }
function setPairAddress(address _pairAddress) public onlyOwner {
        pair = _pairAddress;
        isDividendExempt[pair] = true;
    }
    
}