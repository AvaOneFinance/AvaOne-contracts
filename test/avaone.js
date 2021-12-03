const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AvaOne", function () {
  it("Should create and mint the ERC20 Token", async function () {
    const [owner, addr1, addr2] = await ethers.getSigners();
    const AvaOne = await ethers.getContractFactory("contracts/AvaOne.sol:AvaOne");
    const avaone = await AvaOne.deploy();
    await avaone.deployed();

    expect(await avaone.totalSupply()).to.equal(0);

    const mintTx = await avaone.mint(addr1.address, 100000000000);

    // wait until the transaction is mined
    await mintTx.wait();

    console.log(avaone.address)
    // Tell addr1 to send 1000 (wei) tokens to the addr2
    const send1000Tx = await avaone.connect(addr1).transfer(addr2.address, 1000)

    await send1000Tx.wait()

    expect(await avaone.balanceOf(addr1.address)).to.equal(99999999000);
    expect(await avaone.balanceOf(addr2.address)).to.equal(1000)

    // Burn the 1000 tokens from the addr2

    const burn1000Tx = await avaone.connect(addr2).burn(avaone.balanceOf(addr2.address))

    await burn1000Tx.wait() 

    expect(await avaone.balanceOf(addr2.address)).to.equal(0)
    expect(await avaone.totalSupply()).to.equal(99999999000);
  });
});
