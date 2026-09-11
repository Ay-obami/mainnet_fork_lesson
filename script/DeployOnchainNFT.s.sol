// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {OnchainSVG721, Base64} from "../src/OnchainSVG721.sol";

contract DeployOnchainNFT is Script {
    using Base64 for bytes;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        // Defaults to the assignment artwork in assets/. You can override it with SVG_PATH.
        string memory svgPath = vm.envOr("SVG_PATH", string("assets/keZLB01.svg"));
        string memory svg = vm.readFile(svgPath);
        string memory imageURI = string.concat("data:image/svg+xml;base64,", bytes(svg).encode());

        string memory metadata = string.concat(
            '{"name":"Ayo Fully Onchain SVG #0",',
            '"description":"A fully onchain ERC-721 with SVG artwork and JSON metadata stored entirely in EVM bytecode pages.",',
            '"image":"', imageURI, '","attributes":[',
            '{"trait_type":"Storage","value":"Fully Onchain"},',
            '{"trait_type":"Image Format","value":"SVG"},',
            '{"trait_type":"Storage Method","value":"EVM Bytecode Pages"}',
            "]}"
        );

        vm.startBroadcast(privateKey);
        OnchainSVG721 nft = new OnchainSVG721();
        nft.saveFile("image.svg", bytes(svg));
        nft.saveFile("metadata.json", bytes(metadata));
        nft.mint(deployer);
        vm.stopBroadcast();

        console2.log("SVG path:", svgPath);
        console2.log("SVG bytes:", bytes(svg).length);
        console2.log("NFT contract:", address(nft));
        console2.log("NFT owner:", deployer);
        console2.log("Token ID:", uint256(0));
    }
}
