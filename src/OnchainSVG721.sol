// Repository: https://github.com/Ay-obami/mainnet_fork_lesson
// Commit: 8c0d5f0c6ff49ee3af72c3a8123d16a56eda5baf
// Testnet: <TO_BE_FILLED_AFTER_DEPLOYMENT>
// Contract: <TO_BE_FILLED_AFTER_DEPLOYMENT>
// Deployment transaction: <TO_BE_FILLED_AFTER_DEPLOYMENT>
// Mint transaction: <TO_BE_FILLED_AFTER_DEPLOYMENT>

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        uint256 encodedLength = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLength);
        uint256 j;
        for (uint256 i; i < data.length; i += 3) {
            uint256 a = uint8(data[i]);
            uint256 b = i + 1 < data.length ? uint8(data[i + 1]) : 0;
            uint256 c = i + 2 < data.length ? uint8(data[i + 2]) : 0;
            uint256 packed = (a << 16) | (b << 8) | c;
            result[j++] = TABLE[(packed >> 18) & 0x3f];
            result[j++] = TABLE[(packed >> 12) & 0x3f];
            result[j++] = i + 1 < data.length ? TABLE[(packed >> 6) & 0x3f] : bytes1("=");
            result[j++] = i + 2 < data.length ? TABLE[packed & 0x3f] : bytes1("=");
        }
        return string(result);
    }
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC721Metadata is IERC721 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

contract OnchainSVG721 is IERC721Metadata {
    using Base64 for bytes;

    struct StoredFile {
        address pointer;
        uint32 size;
        bool exists;
    }

    error AlreadyMinted();
    error FileAlreadyExists();
    error FileMissing();
    error InvalidReceiver();
    error NotAuthorized();
    error NotOwner();
    error PageTooLarge();
    error ZeroAddress();
    error EmptyData();
    error DataDeploymentFailed();

    address public immutable contractOwner;
    bool public minted;
    mapping(bytes32 => StoredFile) private _files;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    modifier onlyOwner() {
        if (msg.sender != contractOwner) revert NotOwner();
        _;
    }

    constructor() {
        contractOwner = msg.sender;
    }

    function name() external pure override returns (string memory) {
        return "Ayo Fully Onchain SVG";
    }

    function symbol() external pure override returns (string memory) {
        return "AYOSVG";
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId;
    }

    function balanceOf(address account) external view override returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view override returns (address tokenOwner) {
        tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert FileMissing();
    }

    function approve(address to, uint256 tokenId) external override {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner && !_operatorApprovals[tokenOwner][msg.sender]) revert NotAuthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        ownerOf(tokenId);
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address tokenOwner, address operator) external view override returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        if (to == address(0)) revert ZeroAddress();
        address tokenOwner = ownerOf(tokenId);
        if (tokenOwner != from || !_isAuthorized(msg.sender, tokenId, tokenOwner)) revert NotAuthorized();
        delete _tokenApprovals[tokenId];
        unchecked {
            _balances[from]--;
            _balances[to]++;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 selector) {
                if (selector != IERC721Receiver.onERC721Received.selector) revert InvalidReceiver();
            } catch {
                revert InvalidReceiver();
            }
        }
    }

    function saveFile(string calldata key, bytes calldata data) external onlyOwner {
        if (data.length == 0) revert EmptyData();
        if (data.length > 24_000) revert PageTooLarge();
        bytes32 fileKey = keccak256(bytes(key));
        if (_files[fileKey].exists) revert FileAlreadyExists();
        bytes memory payload = data;
        uint16 payloadSize = uint16(payload.length);
        bytes memory creationCode = abi.encodePacked(
            hex"61", bytes2(payloadSize), hex"600e60003961", bytes2(payloadSize), hex"6000f3", payload
        );
        address pointer;
        assembly {
            pointer := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (pointer == address(0)) revert DataDeploymentFailed();
        _files[fileKey] = StoredFile({pointer: pointer, size: uint32(payload.length), exists: true});
    }

    function getFile(string memory key) public view returns (bytes memory output) {
        StoredFile memory file = _files[keccak256(bytes(key))];
        if (!file.exists) revert FileMissing();
        output = new bytes(file.size);
        address pointer = file.pointer;
        uint256 size = file.size;
        assembly {
            extcodecopy(pointer, add(output, 0x20), 0, size)
        }
    }

    function filePointer(string calldata key) external view returns (address pointer, uint256 size) {
        StoredFile memory file = _files[keccak256(bytes(key))];
        if (!file.exists) revert FileMissing();
        return (file.pointer, file.size);
    }

    function mint(address to) external onlyOwner returns (uint256 tokenId) {
        if (minted) revert AlreadyMinted();
        if (to == address(0)) revert ZeroAddress();
        if (!_files[keccak256(bytes("image.svg"))].exists) revert FileMissing();
        if (!_files[keccak256(bytes("metadata.json"))].exists) revert FileMissing();
        minted = true;
        tokenId = 0;
        _owners[tokenId] = to;
        _balances[to] = 1;
        emit Transfer(address(0), to, tokenId);
    }

    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        ownerOf(tokenId);
        return string.concat("data:application/json;base64,", getFile("metadata.json").encode());
    }

    function rawSVG() external view returns (string memory) {
        return string(getFile("image.svg"));
    }

    function rawMetadata() external view returns (string memory) {
        return string(getFile("metadata.json"));
    }

    function _isAuthorized(address spender, uint256 tokenId, address tokenOwner) internal view returns (bool) {
        return spender == tokenOwner || _tokenApprovals[tokenId] == spender || _operatorApprovals[tokenOwner][spender];
    }
}
