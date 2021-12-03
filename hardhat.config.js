require("@nomiclabs/hardhat-waffle");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      // accounts: [{privateKey: process.env.PRIVATE_KEY, balance: "100000000000000000000"}],
      chainId: 43114,
      forking: {
        url: "https://api.avax.network/ext/bc/C/rpc",
      }
    },
    fuji: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      // accounts: [process.env.PRIVATE_KEY]
    },
    mainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      // accounts: [process.env.PRIVATE_KEY]
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.5.16"
      },
      {
        version: "0.6.2"
      },
      {
        version: "0.6.4"
      },
      {
        version: "0.6.12"
      },
      {
        version: "0.7.0"
      },
      {
        version: "0.8.0"
      }
    ]
  },
};
