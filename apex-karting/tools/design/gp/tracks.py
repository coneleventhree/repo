"""Per-circuit settings for fit_gp.py. Distances (s) are real metres from the
start line along the GeoJSON line; `cuts` = (s inside the straight, new
length in studs); `names` = (s0, s1, corner name); `bank` = name -> degrees;
`ymin` = (s0, s1, studs): raise segment ends in that range (banked corners
must stand above the lawn: the inside edge drops by width/2 x sin(bank));
`ymax` likewise lowers them; `pairsep` = ((s0, s1), (s0, s1), studs) keeps
two stretches apart."""

def turns(*spans):
    return [(a, b, n) for a, b, n in spans]

TRACKS = {
    "Catalunya": dict(
        gid="es-1991", K=0.8, RMIN=32, SEP=52, GRADE=0.075,
        cuts=[(0, 680, 370.0, [(1320, 1550), (2300, 2400), (3770, 3910)]),
              (2860, 3330, 290.0, [(850, 930), (1810, 1960)])],
        LEVEL1=150, KINK=2.5,
        names=turns(
            (640, 755, "Turn 1"), (755, 860, "Turn 2"), (880, 1350, "Turn 3"),
            (1530, 1830, "Turn 4"), (1930, 2100, "Turn 5"), (2130, 2370, "Turn 6"),
            (2380, 2475, "Turn 7"), (2475, 2580, "Turn 8"), (2680, 2870, "Turn 9"),
            (3320, 3510, "Turn 10"), (3510, 3565, "Turn 11"), (3565, 3740, "Turn 12"),
            (3860, 4070, "Turn 13"), (4100, 4320, "Turn 14")),
        width={0: 30},
    ),
    "Zandvoort": dict(
        gid="nl-1948", K=0.8, RMIN=32, SEP=58, GRADE=0.07, KY=1.3, LEVEL1=140,
        cuts=[(0, 380, 230.0, [(510, 620), (1880, 2080), (3300, 3530)])],
        KINK=2.5, STRAIGHT_K=0.003,
        names=turns(
            (360, 560, "Tarzan"), (570, 820, "Gerlach"), (820, 1010, "Hugenholtz"),
            (1010, 1260, "Hunserug"), (1260, 1420, "Slotemaker"), (1600, 1960, "Scheivlak"),
            (2050, 2275, "Mastersbocht"), (2275, 2460, "Turn 9"), (2470, 2700, "Turn 10"),
            (3140, 3330, "Hans Ernst"), (3500, 3690, "Turn 13"), (3690, 4010, "Arie Luyendyk")),
        bank={"Hugenholtz": 12, "Arie Luyendyk": 9},
        # the Hugenholtz exit passes Hans Ernst's gravel: under 6 studs above it
        # (TrackLayout.CrossingClear) its embankment still reaches the ground
        ymax=[(820, 1010, 3.6), (960, 1075, 5.0)],
        ymin=[(800, 1020, 3.2), (3680, 4010, 3.0)],
        width={0: 28},
    ),
    "YasMarina": dict(
        gid="ae-2009", K=0.8, RMIN=32, SEP=58, GRADE=0.04, HPCT=15, HWIN=121, LEVEL1=140,
        cuts=[(1490, 2510, 580.0, [(990, 1260), (310, 470), (815, 895)]),
              (2900, 3490, 260.0, [(3780, 3945), (4000, 4090), (4560, 4710)])],
        KINK=2.5,
        names=turns(
            (200, 350, "Turn 1"), (480, 580, "Turn 2"), (590, 860, "Turn 3"),
            (860, 1010, "Turn 4"), (1200, 1420, "Turn 5"), (2510, 2620, "Turn 6"),
            (3480, 3820, "Turn 9"), (3900, 4000, "Turn 10"), (4060, 4130, "Turn 11"),
            (4200, 4290, "Turn 12"), (4290, 4530, "Turn 13"), (4680, 4870, "Turn 15"),
            (4950, 5070, "Turn 16")),
        bank={"Turn 9": 6},
        ymin=[(3480, 3830, 2.0)],
        width={0: 30},
    ),
}
