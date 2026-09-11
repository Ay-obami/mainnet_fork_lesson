// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {OnchainSVG721, Base64} from "../src/OnchainSVG721.sol";

contract RecoverOnchainNFT is Script {
    using Base64 for bytes;

    address constant NFT =
        0xA693C80595C76cA8b98759c3322bDC00a7586fD6;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        string memory svgPath =
            vm.envOr("SVG_PATH", string("assets/keZLB01.svg"));

        string memory svg = vm.readFile(svgPath);

        string memory imageURI = string.concat(
            "data:image/svg+xml;base64,",
            bytes(svg).encode()
        );

        string memory metadata = string.concat(
            '{"name":"Ayo Fully Onchain SVG #0",',
            '"description":"A fully onchain ERC-721 with SVG artwork and JSON metadata stored entirely in EVM bytecode pages.",',
            '"image":"',
            imageURI,
            '","attributes":[',
            '{"trait_type":"Storage","value":"Fully Onchain"},',
            '{"trait_type":"Image Format","value":"SVG"},',
            '{"trait_type":"Storage Method","value":"EVM Bytecode Pages"}',
            "]}"
        );

        OnchainSVG721 nft = OnchainSVG721(NFT);

        vm.startBroadcast(privateKey);

        nft.saveFile("image.svg", bytes(svg));
        nft.saveFile("metadata.json", bytes(metadata));
        nft.mint(deployer);

        vm.stopBroadcast();
    }
}