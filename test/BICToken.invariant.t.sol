// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BICToken} from "../src/BICToken.sol";

/// @dev All transfers stay within this finite actor set so conservation is measurable.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    BICToken public immutable token;
    address[5] public actors;

    // An independent ledger of requested movements. Never resynchronize it from token storage:
    // a wrong debit/credit must fail the property, rather than constrain subsequent inputs.
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(BICToken token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordMovement(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Explicitly exercise revocation, infinite approval, and the adjacent finite value.
        uint256 mode = amount % 5;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance(from);
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) expectedAllowance[from][spender] = approved - amount;
        _recordMovement(from, to, amount);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        uint256 index = _fundedIndex(fromSeed);
        address from = actors[index];
        address to = actors[(index + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = expectedBalance(from);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordMovement(from, to, amount);
    }

    function approveAndTransferFrom(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amount,
        bool infinite
    ) external {
        address from = actors[_fundedIndex(fromSeed)];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 1, expectedBalance(from));
        _approve(from, spender, infinite ? type(uint256).max : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (!infinite) expectedAllowance[from][spender] = 0;
        _recordMovement(from, to, amount);
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance(from);
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, expectedBalance(from));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
    }

    function rejectApproveToZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function rejectTransferFromAboveAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        if (approved == type(uint256).max) {
            approved = bound(amount, 0, SUPPLY);
            _approve(from, spender, approved);
        }
        amount = bound(amount, approved + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectTransferFromAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance(from);
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(from, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
        // No ghost allowance debit: a rejected transfer must roll its allowance spending back.
    }

    function rejectTransferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance(from));
        _approve(from, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
    }

    function revokeAndRejectSpending(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(from, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(from, to, 1);
    }

    function expectedBalance(address account) public view returns (uint256) {
        uint256 initial = account == actors[0] ? SUPPLY : 0;
        return initial + received[account] - sent[account];
    }

    function _fundedIndex(uint256 seed) internal view returns (uint256 index) {
        index = seed % actors.length;
        // Bounded search makes full-balance and approved-spending actions nonzero,
        // even after random transfers have concentrated the entire supply in one account.
        for (uint256 i; i < actors.length; ++i) {
            if (expectedBalance(actors[index]) > 0) return index;
            index = (index + 1) % actors.length;
        }
        revert("handler ledger lost the fixed supply");
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _recordMovement(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract BICTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    BICToken internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new BICToken();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));
        for (uint256 i = 1; i < 5; ++i) {
            handler.transfer(0, i, SUPPLY / 5);
        }
        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferFullBalance.selector;
        selectors[4] = TokenHandler.rejectTransferAboveBalance.selector;
        selectors[5] = TokenHandler.rejectTransferToZero.selector;
        selectors[6] = TokenHandler.rejectApproveToZero.selector;
        selectors[7] = TokenHandler.rejectTransferFromAboveAllowance.selector;
        selectors[8] = TokenHandler.rejectTransferFromAboveBalance.selector;
        selectors[9] = TokenHandler.rejectTransferFromToZero.selector;
        selectors[10] = TokenHandler.revokeAndRejectSpending.selector;
        selectors[11] = TokenHandler.approveAndTransferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsFixedAndBalancesConserved() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "Bankers In Control");
        assertEq(token.symbol(), "BIC");
        assertEq(token.decimals(), 18);
    }

    function invariant_EachBalanceMatchesAuthorizedMovements() public view {
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "unauthorized or incorrect movement");
        }
    }

    function invariant_AllowancesMatchApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < 5; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "approval isolation, spending, or rollback violated"
                );
            }
        }
    }

    /// @dev Every holder can still transfer its entire balance after an arbitrary sequence.
    function afterInvariant() public {
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            uint256 balance = handler.expectedBalance(actor);
            vm.prank(actor);
            assertTrue(token.transfer(address(this), balance));
            assertEq(token.balanceOf(actor), 0);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
