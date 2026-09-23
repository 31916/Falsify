"""Independent monitor agreement on saved traces and strict-boundary tests."""
import sys
from pathlib import Path
import numpy as np
from scipy.io import loadmat
from staliro.specifications import RTAMTDense
from run_fim_psy import margins, FORMULAS, NAMES


def check(y, t):
    m = margins(y)
    actual = [RTAMTDense(phi, {name:i}).evaluate(m, t)
              for i, (phi,name) in enumerate(zip(FORMULAS,NAMES))]
    np.testing.assert_allclose(actual, m.min(axis=0), rtol=0, atol=1e-9)
    return min(actual)


def main():
    for rpm, gear in [(600,1),(6000,4),(599,1),(6001,4),(1000,.5),(1000,4.5),(0,1),(7000,5)]:
        y = np.tile([1000,0,2], (3001,1)).astype(float)
        y[-1] = [rpm,0,gear]
        check(y, np.linspace(0,30,3001))
    run = Path(sys.argv[1])
    files = sorted((run/'exp1').glob('*.mat'))
    assert len(files) == 132
    for file in files:
        tr = loadmat(file, simplify_cells=True)['trace']
        assert abs(check(tr['Y'], tr['T'])-tr['Rho']) < 1e-9, file
    print('PASS: RTAMT dense vs analytic: 132 existing traces + 8 endpoint/boundary tests')


if __name__ == '__main__':
    main()
