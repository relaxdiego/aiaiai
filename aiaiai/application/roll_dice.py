from aiaiai.domain import dice


def roll_dice(n_dice: int) -> list[int]:
    """Roll n_dice 6-sided dice and return the results."""
    return dice.roll(n_dice)
