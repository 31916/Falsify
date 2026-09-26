"""Predeclared fixed screen: six examples + 64 corners + 64 seeded LHS; 130 unique."""
import itertools


def fixed_inputs():
    from scipy.stats import qmc
    representatives = [[60]*6,[80]*6,[100]*6,[60,60,60,100,100,100],
                       [100,100,100,60,60,60],[80,80,100,100,80,80]]
    groups=[('representative',representatives),
            ('corner',itertools.product([60.,100.],repeat=6)),
            ('lhs',60+40*qmc.LatinHypercube(d=6,seed=20260926).random(64))]
    rows=[]; seen=set()
    for group,values in groups:
        for vector in values:
            key=tuple(float(v) for v in vector)
            if key in seen:
                continue
            seen.add(key)
            row=dict(InputID=f'I{len(rows)+1:03d}',Source=group)
            row.update({f'Throttle{5*i}':v for i,v in enumerate(key)})
            rows.append(row)
    assert len(rows)==130
    return rows
