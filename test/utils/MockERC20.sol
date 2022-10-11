// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.0;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 amount) ERC20("Token", "TKN") {
        _mint(msg.sender, amount);
    }
}
