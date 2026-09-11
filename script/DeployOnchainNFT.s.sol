// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {OnchainSVG721, Base64} from "../src/OnchainSVG721.sol";

contract DeployOnchainNFT is Script {
    using Base64 for bytes;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600">',
            '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">',
            '<stop offset="0%" stop-color="#111827"/>',
            '<stop offset="100%" stop-color="#312e81"/>',
            "</linearGradient></defs>",
            '<rect width="600" height="600" rx="48" fill="url(#bg)"/>',
            '<circle cx="300" cy="245" r="135" fill="none" stroke="#22d3ee" stroke-width="18"/>',
            '<circle cx="300" cy="245" r="94" fill="#0f172a" stroke="#a78bfa" stroke-width="10"/>',
            '<path d="M235 270 L300 160 L365 270 Z" fill="#22d3ee" opacity="0.85"/>',
            '<circle cx="300" cy="245" r="24" fill="#f8fafc"/>',
            '<text x="300" y="445" text-anchor="middle" font-family="monospace" font-size="42" font-weight="bold" fill="#f8fafc">ONCHAIN</text>',
            '<text x="300" y="493" text-anchor="middle" font-family="monospace" font-size="22" fill="#67e8f9">ERC-721 #0</text>',
            "</svg>"
        );

        string memory imageURI = string.concat("data:image/svg+xml;base64,", bytes(svg).encode());

        string memory metadata = string.concat(
            '{"name":"Ayo Fully Onchain SVG #0",',
            '"description":"A fully onchain ERC-721 with SVG artwork and JSON metadata stored in EVM bytecode.",',
            '"image":"',
            imageURI,
            '","attributes":[',
            '{"trait_type":"Storage","value":"Fully Onchain"},',
            '{"trait_type":"Image Format","value":"SVG"},',
            '{"trait_type":"Storage Method","value":"EVM Bytecode"}',
            "]}"
        );

        vm.startBroadcast(privateKey);
        OnchainSVG721 nft = new OnchainSVG721();
        nft.saveFile("image.svg", bytes(svg));
        nft.saveFile("metadata.json", bytes(metadata));
        nft.mint(deployer);
        vm.stopBroadcast();

        console2.log("NFT contract:", address(nft));
        console2.log("NFT owner:", deployer);
        console2.log("Token ID:", uint256(0));
    }
}
