from fastmcp import FastMCP

from aiaiai.application import roll_dice as roll_dice_use_case

mcp = FastMCP(name="Relaxdiego's Tools")


@mcp.tool
def roll_dice(n_dice: int) -> list[int]:
    """Roll `n_dice` 6-sided dice and return the results."""
    return roll_dice_use_case.roll_dice(n_dice)


if __name__ == "__main__":
    mcp.run()
