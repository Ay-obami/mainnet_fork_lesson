// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OnchainSVG721, Base64} from "../src/OnchainSVG721.sol";

contract OnchainSVG721Test is Test {
    using Base64 for bytes;

    OnchainSVG721 internal nft;
    address internal recipient = address(0xBEEF);

    function setUp() public {
        nft = new OnchainSVG721();
    }

    function testStoresFilesMintsAndReturnsDataURI() public {
        string memory svg = '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>';
        string memory imageURI = string.concat("data:image/svg+xml;base64,", bytes(svg).encode());
        string memory metadata = string.concat('{"name":"Test #0","image":"', imageURI, '"}');

        nft.saveFile("image.svg", bytes(svg));
        nft.saveFile("metadata.json", bytes(metadata));
        nft.mint(recipient);

        assertEq(nft.ownerOf(0), recipient);
        assertEq(nft.balanceOf(recipient), 1);
        assertEq(nft.rawSVG(), svg);
        assertEq(nft.rawMetadata(), metadata);

        string memory expected = string.concat("data:application/json;base64,", bytes(metadata).encode());
        assertEq(nft.tokenURI(0), expected);
    }

    function testFileStorageUsesSeparateBytecodeContract() public {
        bytes memory svg = bytes('<svg xmlns="http://www.w3.org/2000/svg"></svg>');
        nft.saveFile("image.svg", svg);

        (address pointer, uint256 size) = nft.filePointer("image.svg");
        assertTrue(pointer.code.length > 0);
        assertEq(pointer.code.length, size);
        assertEq(size, svg.length);
        assertEq(nft.rawSVG(), string(svg));
    }

    function testMintRequiresBothFiles() public {
        nft.saveFile("image.svg", bytes("<svg/>"));
        vm.expectRevert(OnchainSVG721.FileMissing.selector);
        nft.mint(recipient);
    }

    function testOnlyOwnerCanUpload() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert(OnchainSVG721.NotOwner.selector);
        nft.saveFile("image.svg", bytes("<svg/>"));
    }
}
