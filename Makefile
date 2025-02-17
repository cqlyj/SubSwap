-include .env

install:
	@forge install OpenZeppelin/openzeppelin-contracts@v5.2.0 --no-commit && forge install uniswap/v4-core --no-commit && forge install uniswap/v4-periphery --no-commit && forge install OpenZeppelin/uniswap-hooks --no-commit
