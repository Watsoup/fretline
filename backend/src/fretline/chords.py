"""Open-position chord shapes (frets low E -> high e, -1 = muted).

Lookup data for the chord detector / lesson builder. Extend as needed.
"""

SHAPES: dict[str, list[int]] = {
    "C": [-1, 3, 2, 0, 1, 0],
    "D": [-1, -1, 0, 2, 3, 2],
    "E": [0, 2, 2, 1, 0, 0],
    "F": [1, 3, 3, 2, 1, 1],
    "G": [3, 2, 0, 0, 0, 3],
    "A": [-1, 0, 2, 2, 2, 0],
    "B": [-1, 2, 4, 4, 4, 2],
    "Am": [-1, 0, 2, 2, 1, 0],
    "Bm": [-1, 2, 4, 4, 3, 2],
    "Dm": [-1, -1, 0, 2, 3, 1],
    "Em": [0, 2, 2, 0, 0, 0],
    "F#m": [2, 4, 4, 2, 2, 2],
    "A7": [-1, 0, 2, 0, 2, 0],
    "B7": [-1, 2, 1, 2, 0, 2],
    "C7": [-1, 3, 2, 3, 1, 0],
    "D7": [-1, -1, 0, 2, 1, 2],
    "E7": [0, 2, 0, 1, 0, 0],
    "G7": [3, 2, 0, 0, 0, 1],
    "Cadd9": [-1, 3, 2, 0, 3, 0],
    "Dsus4": [-1, -1, 0, 2, 3, 3],
    "Asus2": [-1, 0, 2, 2, 0, 0],
    "Fmaj7": [-1, -1, 3, 2, 1, 0],
    "N": [-1, -1, -1, -1, -1, -1],  # no chord
}

# Easier stand-ins for hard shapes (stepping stones, design doc rule 6).
EASY: dict[str, str] = {
    "F": "Fmaj7",
    "Bm": "Bm",  # TODO: add a 4-string Bm voicing
    "F#m": "F#m",
}


def shape(name: str) -> list[int]:
    """Frets for a chord name, all-muted if unknown."""
    return list(SHAPES.get(name, SHAPES["N"]))
