// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NexusEtherealsNFT is ERC721Enumerable, Ownable {
    using Strings for uint256;

    string public baseURI;
    string public baseExtension = ".json";
    string public notRevealedUri;

    uint256 public cost = 3 ether;
    uint256 public maxSupply = 11111;
    uint256 public maxMintAmount = 50;
    uint256 public maxNFTPerAddress = 222;

    uint256 public whitelistDiscount = 0 ether;

    bool public paused = false;
    bool public revealed = false;

    mapping(address => bool) public whitelist;
    mapping(address => uint256) private whitelistIndices;

    uint256 public whitelistCount;
    bool public whitelistEnabled = true;

    event AddressAdded(address indexed _address);
    event AddressRemoved(address indexed _address);
    event WhitelistToggled(bool _enabled);

    mapping(address => uint256) public addressMintedBalance;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initBaseURI,
        string memory _initNotRevealedUri
    ) ERC721(_name, _symbol) {
        setBaseURI(_initBaseURI);
        setNotRevealedURI(_initNotRevealedUri);
    }

    // internal
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // public
    function mint(uint256 _mintAmount) public payable {
        require(!paused, "the contract is paused");
        uint256 supply = totalSupply();
        require(_mintAmount > 0, "need to mint at least 1 NFT");
        require(
            _mintAmount <= maxMintAmount,
            "max mint amount per session exceeded"
        );
        require(supply + _mintAmount <= maxSupply, "max NFT limit exceeded");

        uint256 costToMint = isWhitelisted(msg.sender) && whitelistEnabled
            ? cost - whitelistDiscount
            : cost;

        if (msg.sender != owner()) {
            require(
                msg.value >= costToMint * _mintAmount,
                "insufficient funds"
            );
            require(
                addressMintedBalance[msg.sender] + _mintAmount <=
                    maxNFTPerAddress,
                "max NFT per address exceeded"
            );
        }

        for (uint256 i = 1; i <= _mintAmount; i++) {
            addressMintedBalance[msg.sender]++;
            _safeMint(msg.sender, supply + i);
        }
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed == false) {
            return notRevealedUri;
        }

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }

    function getWhitelistCount() public view returns (uint256) {
        return whitelistCount;
    }

    function getWhitelistDiscount() external view returns (uint256) {
        return whitelistDiscount;
    }

    //only owner
    function reveal(bool _state) public onlyOwner {
        revealed = _state;
    }

    function setmaxNFTPerAddress(uint256 _limit) public onlyOwner {
        maxNFTPerAddress = _limit;
    }

    function setCost(uint256 _newCost) public onlyOwner {
        cost = _newCost;
    }

    function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner {
        maxMintAmount = _newmaxMintAmount;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension)
        public
        onlyOwner
    {
        baseExtension = _newBaseExtension;
    }

    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedUri = _notRevealedURI;
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    function addToWhitelist(address[] calldata _addresses) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            if (!whitelist[_addresses[i]]) {
                whitelist[_addresses[i]] = true;
                whitelistIndices[_addresses[i]] = whitelistCount;
                whitelistCount++;
                emit AddressAdded(_addresses[i]);
            }
        }
    }

    function removeFromWhitelist(address[] calldata _addresses)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < _addresses.length; i++) {
            if (whitelist[_addresses[i]]) {
                whitelist[_addresses[i]] = false;
                whitelistIndices[_addresses[i]] = 0;
                whitelistCount--;
                emit AddressRemoved(_addresses[i]);
            }
        }
    }

    function toggleWhitelist(bool _enabled) public onlyOwner {
        whitelistEnabled = _enabled;
        emit WhitelistToggled(_enabled);
    }

    function setWhitelistDiscount(uint256 discount) external onlyOwner {
        whitelistDiscount = discount;
    }

    function withdraw(address to) public payable onlyOwner {
        // =============================================================================
        // Do not remove this otherwise you will not be able to withdraw the funds.
        // =============================================================================
        (bool os, ) = payable(to).call{value: address(this).balance}("");
        require(os);
        // =============================================================================
    }
}
