pragma solidity ^0.4.25;

// ----------------------------------------------------------------------------
// Deepyr's ERC20 receiving dividend token contract based on yarrumretep's
// Dividend Token contract
// For research purposes only. NOT to be used for tokens of any value
//
//
//
// (c) Adrian Guerrera / Deepyr Pty Ltd 2019. The MIT Licence.
//
// Code borrowed from various authors mentioned and from contracts
// (c) BokkyPooBah / Bok Consulting Pty Ltd 2018. The MIT Licence.
// ----------------------------------------------------------------------------



// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------
library SafeMath {
  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
      c = a + b;
      require(c >= a);
  }
  function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
      require(b <= a);
      c = a - b;
  }
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
      c = a * b;
      require(a == 0 || c / a == b);
  }
  function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
      require(b > 0);
      c = a / b;
  }
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
    return a % b;
  }
}

// ----------------------------------------------------------------------------
// ERC Token Standard #20 Interface
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
// ----------------------------------------------------------------------------
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address _who) external view returns (uint256);
    function allowance(address _owner, address _spender)  external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value)  external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value)  external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value  );
    event Approval(address indexed owner, address indexed spender, uint256 value  );
}

// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------
contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public;
}

// ----------------------------------------------------------------------------
// Owned contract
// ----------------------------------------------------------------------------
contract Owned {
    address public owner;
    address public newOwner;
    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
    }
    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

// ----------------------------------------------------------------------------
// Implementation of the basic standard token.
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
// Originally based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
// ----------------------------------------------------------------------------

contract DividendToken is IERC20, Owned {
    using SafeMath for uint256;


    //mapping (address => uint256) private accounts;
    mapping (address => mapping (address => uint256)) private allowed_;
    string public name;
    string public symbol;
    uint256 private totalSupply_;
    uint8 public decimals;

    bool public mintable = true;
    bool public transferable = false;

    // Dividends
    uint256 constant pointMultiplier = 10e32;
    IERC20 public dividendTokenAddress;

    struct Account {
        uint256 balance;
        uint256 lastDividendPoints;
    }
    mapping(address => Account) public accounts;

    uint256 public totalDividendPoints;
    uint256 public unclaimedDividends;
    mapping(address => uint256) public unclaimedDividendByAccount;  // [account][token]

    event Mint(address indexed to, uint256 amount);
    event MintStarted();
    event MintFinished();
    event TransfersEnabled();
    event TransfersDisabled();

    event DividendReceived(uint256 time, address indexed sender, uint256 amount);
    event WithdrawalDividends(address indexed holder, address indexed token, uint256 amount);
    event LogUint(uint256 amount, string msglog);

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor() public {
        name = "Deepyrs Dividend Token";
        symbol = "DEEPYR";
        decimals = 18;
        totalSupply_ = 10000000 * 10**uint(decimals);
        transferable = true;
        accounts[owner].balance = totalSupply_;
        dividendTokenAddress = IERC20(0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359);
        emit Transfer(address(0), owner, totalSupply_);
    }

    modifier canMint() {
        require(mintable);
        _;
    }

    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address _owner) public view returns (uint256) {
        return accounts[_owner].balance;
    }

    function allowance(  address _owner,  address _spender )  public  view  returns (uint256) {
        return allowed_[_owner][_spender];
    }

    function approve(address _spender, uint256 _value) public returns (bool) {
        require(transferable);
        allowed_[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }


    function transfer(address _to, uint256 _value) public returns (bool) {
        require(transferable);
        require(_value <= accounts[msg.sender].balance);
        require(_to != address(0));

        // Added for dividends
        _updateAccount(msg.sender);
        _updateAccount(_to);

        accounts[msg.sender].balance = accounts[msg.sender].balance.sub(_value);
        accounts[_to].balance = accounts[_to].balance.add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(  address _from,  address _to,uint256 _value )  public returns (bool) {
        require(transferable);
        require(_value <= accounts[_from].balance);
        require(_value <= allowed_[_from][msg.sender]);
        require(_to != address(0));

        // Added for dividends
        _updateAccount(_from);
        _updateAccount(_to);

        accounts[_from].balance = accounts[_from].balance.sub(_value);
        accounts[_to].balance = accounts[_to].balance.add(_value);
        allowed_[_from][msg.sender] = allowed_[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }


    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     * approve should be called when allowed_[_spender] == 0. To increment
     * allowed value is better to use this function to avoid 2 calls (and wait until
     * the first transaction is mined)
     * From MonolithDAO Token.sol
     */
    function increaseApproval(address _spender, uint256 _addedValue) public returns (bool) {
        allowed_[msg.sender][_spender] = (allowed_[msg.sender][_spender].add(_addedValue));
        emit Approval(msg.sender, _spender, allowed_[msg.sender][_spender]);
        return true;
    }

    function decreaseApproval(address _spender, uint256 _subtractedValue) public returns (bool) {
        uint256 oldValue = allowed_[msg.sender][_spender];
        if (_subtractedValue >= oldValue) {
          allowed_[msg.sender][_spender] = 0;
        } else {
          allowed_[msg.sender][_spender] = oldValue.sub(_subtractedValue);
        }
        emit Approval(msg.sender, _spender, allowed_[msg.sender][_spender]);
        return true;
    }

    // ------------------------------------------------------------------------
    // Mint & Burn functions, both interrnal and external
    // ------------------------------------------------------------------------
    function _mint(address _account, uint256 _amount) internal {
        require(_account != 0);

        // Added for dividends
        _updateAccount(_account);

        totalSupply_ = totalSupply_.add(_amount);
        accounts[_account].balance = accounts[_account].balance.add(_amount);
        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != 0);
        require(_amount <= accounts[_account].balance);

        // Added for dividends
        _updateAccount(_account);

        totalSupply_ = totalSupply_.sub(_amount);
        accounts[_account].balance = accounts[_account].balance.sub(_amount);
        emit Transfer(_account, address(0), _amount);
    }

    function _burnFrom(address _account, uint256 _amount) internal {
        require(_amount <= allowed_[_account][msg.sender]);
        allowed_[_account][msg.sender] = allowed_[_account][msg.sender].sub(_amount);
        _burn(_account, _amount);
    }

    function mint(address _to, uint256 _amount) public onlyOwner canMint returns (bool) {
        _mint(_to, _amount);
        emit Mint(_to, _amount);
        return true;
    }

    function burn(uint256 _value)  public {
        _burn(msg.sender, _value);
    }

    function burnFrom(address _from, uint256 _value) public {
        _burnFrom(_from, _value);
    }

    // ------------------------------------------------------------------------
    // Safety to start and stop minting new tokens.
    // ------------------------------------------------------------------------

    function startMinting() public onlyOwner returns (bool) {
        mintable = true;
        emit MintStarted();
        return true;
    }

    function finishMinting() public onlyOwner canMint returns (bool) {
        mintable = false;
        emit MintFinished();
        return true;
    }

    // ------------------------------------------------------------------------
    // Safety to stop token transfers
    // ------------------------------------------------------------------------

    function enableTransfers() public onlyOwner {
        require(!transferable);
        transferable = true;
        emit TransfersEnabled();
    }

    function disableTransfers() public onlyOwner {
        require(transferable);
        transferable = false;
        emit TransfersDisabled();
    }

    //------------------------------------------------------------------------
    // Dividends
    //------------------------------------------------------------------------

    function dividendsOwing(address account) external view returns(uint256) {
        return _dividendsOwing( account );
    }

    function _dividendsOwing(address account) internal view returns(uint256) {
        uint256 newDividendPoints = totalDividendPoints.sub(accounts[account].lastDividendPoints);
        return (accounts[account].balance * newDividendPoints) / pointMultiplier;
    }

    //------------------------------------------------------------------------
    // Dividends: Token Transfers
    //------------------------------------------------------------------------

     function updateAccount(address _account) public {
        _updateAccount(_account);
    }

    function _updateAccount(address _account) internal {
        uint256 _owing = _dividendsOwing(_account);
        if (_owing > 0) {
            unclaimedDividendByAccount[_account] = unclaimedDividendByAccount[_account].add(_owing);
            accounts[_account].lastDividendPoints = totalDividendPoints;
        }
    }

    //------------------------------------------------------------------------
    // Dividends: Token Deposits
    //------------------------------------------------------------------------

    function approveTokenDividend(uint256 _amount) external  {
        require(_amount > 0);
        require(IERC20(dividendTokenAddress).approve(this, _amount));
    }

    function depositTokenDividend(uint256 _amount) external  {
        require(_amount > 0 );
        // accept tokens
        require(IERC20(dividendTokenAddress).transferFrom(msg.sender, address(this), _amount));
        _depositDividends(_amount);
    }

    function _depositDividends(uint256 amount) internal {
        // Convert deposit into points
        totalDividendPoints += (amount * pointMultiplier ) / totalSupply();
        unclaimedDividends += amount;

        emit DividendReceived(now, msg.sender, amount);
    }

    //------------------------------------------------------------------------
    // Dividends: Claim accrued dividends
    //------------------------------------------------------------------------
    function withdrawDividends () public  {
        _updateAccount(msg.sender);
        _withdrawDividends(msg.sender);
    }
    function withdrawDividendsByAccount (_account) public onlyOwner {
        _updateAccount(_account);
        _withdrawDividends(_account);
    }
    function _withdrawDividends(address _account) internal  {
        uint256 _unclaimed = unclaimedDividendByAccount[_account];
        unclaimedDividends = unclaimedDividends.sub(_unclaimed);
        unclaimedDividendByAccount[_account] = 0;

        _transferDividendTokens(dividendTokenAddress, _account, _unclaimed );
        emit WithdrawalDividends(_account, dividendTokenAddress, _unclaimed);
    }

    function _transferDividendTokens(address _token, address /*_account*/, uint256 /*_amount*/) internal pure  {
            // transfer dividends owed, to be replaced
        if (_token != address(0x0)) {
               require(IERC20(_token).transfer(_account, _amount));
        } else {
               require(transfer(_account, _amount));
        }
    }


    //------------------------------------------------------------------------
    // Dividends: Helper functions
    //------------------------------------------------------------------------
    function setDividendTokenAddress (address _token) public onlyOwner {
        require(_token != address(0));
        dividendTokenAddress = IERC20(_token);
    }

    function _initDividends() internal {
        dividendTokenAddress = IERC20(0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359);
        _depositDividends(msg.value,address(0x0));
    }

    // ------------------------------------------------------------------------
    // Dont accept ETH deposits as dividends
    // ------------------------------------------------------------------------
    function () public payable {
        revert();
    }

    // ------------------------------------------------------------------------
    // Owner can transfer out any accidentally sent ERC20 tokens, please restrict or remove
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address tokenAddress, uint256 tokens) public onlyOwner returns (bool success) {
        return IERC20(tokenAddress).transfer(owner, tokens);
    }
}
