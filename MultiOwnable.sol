// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

abstract contract MultiOwnable {
    address private _ownerSetter;

    address public owner;
    address public ownerGovernance;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        require(
            owner == _msgSender() || ownerGovernance == _msgSender(),
            "User is not owner"
        );
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function ownerSetter() public view virtual returns (address) {
        return _ownerSetter;
    }

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function setOwner(
        address owner_,
        address ownerGovernance_
    ) public onlyOwnerSetter {
        owner = owner_;
        ownerGovernance = ownerGovernance_;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwnerSetter() {
        require(
            ownerSetter() == _msgSender(),
            "Ownable: caller is not the ownerSetter"
        );
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwnerSetter` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnerSetter() public virtual onlyOwnerSetter {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function setOwnerSetter(address newOwner) public virtual onlyOwnerSetter {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _ownerSetter;
        _ownerSetter = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
