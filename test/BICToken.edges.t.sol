// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BICToken} from "../src/BICToken.sol";

/// forge-config: default.fuzz.runs = 1000
contract BICTokenEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    BICToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new BICToken();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
    }

    function test_OneMinorUnitCanBeTransferredSpentAndReturned() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferCannotBypassBalanceWithInfiniteApproval() public {
        uint256 maximum = type(uint256).max;
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(expected);
        token.transfer(alice, maximum);

        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 2);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_InfiniteApprovalCanBeReplacedAndRevokedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 5));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 3));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 2));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 2);
    }

    function test_ExhaustedAllowanceCannotBeReplayedAgainstAnotherRecipient() public {
        assertTrue(token.approve(spender, 7));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 7));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 7);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_AllowanceAuthorizesCallerNotRecipientOrTransactionOrigin() public {
        assertTrue(token.approve(bob, 1));
        // Bob is both recipient and tx.origin, but the immediate caller has no approval.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender, bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), bob), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(bob, spender);
        assertTrue(token.transferFrom(address(this), spender, 1));
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(address(this), bob), 0);
    }

    function test_TransferFromByOwnerRequiresItsOwnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_AllowancesAreIsolatedBetweenOwnersAndSpenders() public {
        assertTrue(token.transfer(alice, 10));
        assertTrue(token.transfer(bob, 20));
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));
        vm.prank(bob);
        assertTrue(token.approve(spender, 11));
        vm.prank(alice);
        assertTrue(token.approve(bob, 13));

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 3));
        assertEq(token.allowance(alice, spender), 4);
        assertEq(token.allowance(bob, spender), 11);
        assertEq(token.allowance(alice, bob), 13);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(bob), 23);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 30);
    }

    function test_ZeroTransferFromPreservesFiniteAndInfiniteApprovalsAndEmits() public {
        uint256[4] memory approvals = [uint256(0), 1, type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(alice);
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(alice, bob, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroApprovalToZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroCallerCannotTransferOrApproveEvenZero() public {
        // Defensive checks for a zero sender, exercised synthetically via prank.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToTokenContractDoesNotBurnOrGiveDeployerAccess() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(token), alice, 1);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_TransferRoundTripPreservesBalancesAndApprovals(
        uint256 aliceFunds,
        uint256 bobFunds,
        uint256 amount,
        uint256 approved
    ) public {
        aliceFunds = bound(aliceFunds, 0, SUPPLY);
        bobFunds = bound(bobFunds, 0, SUPPLY - aliceFunds);
        amount = bound(amount, 0, aliceFunds);
        assertTrue(token.transfer(alice, aliceFunds));
        assertTrue(token.transfer(bob, bobFunds));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));

        assertEq(token.balanceOf(alice), aliceFunds);
        assertEq(token.balanceOf(bob), bobFunds);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceFunds - bobFunds);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransferMatchesSingleTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        BICToken splitToken = new BICToken();
        assertTrue(token.transfer(alice, total));
        assertTrue(splitToken.transfer(alice, first));
        assertTrue(splitToken.transfer(alice, total - first));

        assertEq(splitToken.balanceOf(alice), token.balanceOf(alice));
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(splitToken.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceShortfallCannotSpendFundedBalance(uint256 funds, uint256 approved, uint256 amount)
        public
    {
        funds = bound(funds, 1, SUPPLY);
        approved = bound(approved, 0, funds - 1);
        amount = bound(amount, approved + 1, funds);
        assertTrue(token.transfer(alice, funds));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), funds);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funds);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceShortfallPreservesFiniteAllowance(uint256 funds, uint256 amount, uint256 approved) public {
        funds = bound(funds, 0, SUPPLY);
        amount = bound(amount, funds + 1, type(uint256).max - 1);
        approved = bound(approved, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, funds));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funds, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), funds);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funds);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIsolatedAndIdempotent(uint256 previous, uint256 replacement) public {
        assertTrue(token.approve(spender, previous));
        assertTrue(token.approve(bob, 17));
        vm.prank(alice);
        assertTrue(token.approve(spender, 19));
        assertTrue(token.approve(spender, replacement));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), 17);
        assertEq(token.allowance(alice, spender), 19);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalDoesNotReserveOwnersBalance(uint256 approved) public {
        approved = bound(approved, 1, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
