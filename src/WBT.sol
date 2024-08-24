// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WeatteryBettingToken is ERC20, Ownable {
    mapping(address => bool) private registeredAddresses;

    event AddressRegistered(address indexed _address);
    event AddressRemoved(address indexed _address);

    constructor() ERC20("Weattery Betting Token", "WBT") Ownable(msg.sender) {}

    modifier onlyRegistered() {
        require(registeredAddresses[msg.sender], "Not a registered address");
        _;
    }

    /**
     * @dev Registers an address, granting it the authority to mint tokens.
     * @param _address The address to be registered.
     */
    function registerMintable(address _address) public onlyOwner {
        require(_address != address(0), "Cannot register the zero address");
        require(!registeredAddresses[_address], "Address already registered");

        registeredAddresses[_address] = true;
        emit AddressRegistered(_address);
    }

    /**
     * @dev Removes an address, revoking its authority to mint tokens.
     * @param _address The address to be removed.
     */
    function removeMintable(address _address) public onlyOwner {
        require(_address != address(0), "Cannot remove the zero address");
        require(registeredAddresses[_address], "Address not registered");

        registeredAddresses[_address] = false;
        emit AddressRemoved(_address);
    }

    /**
     * @dev Standard ERC20 `transferFrom` function. If called by a registered address, no prior approval is required.
     * @param from The address from which the tokens will be transferred.
     * @param to The address that will receive the tokens.
     * @param value The amount of tokens to be transferred.
     */
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (!registeredAddresses[msg.sender]) {
            address spender = _msgSender();
            _spendAllowance(from, spender, value);
        }

        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev Mints new tokens and assigns them to a specified address.
     * @param to The address that will receive the newly minted tokens.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyRegistered {
        _mint(to, amount);
    }

    /**
     * @dev Burns a specific amount of tokens from a specified address.
     * @param from The address from which tokens will be burned.
     * @param amount The number of tokens to burn.
     */
    function burn(address from, uint256 amount) public onlyRegistered {
        _burn(from, amount);
    }
}
