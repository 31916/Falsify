"""Independent trace monitor, shared by regression tests (speed mph, time s)."""
import numpy as np


def metrics(data, deadline, target):
    speed,gear=data['SpeedMPH'],data['Gear']
    in_window=data['TimeSeconds']<=deadline+1e-10
    rho=float(speed[in_window].max()-target)
    reach=np.flatnonzero(speed>=target)
    return dict(AccelerationRhoMPH=rho,AccelerationPass=rho>=0,
        GearRangePass=bool(((gear>=1)&(gear<=4)).all()),
        GearDiscretePass=bool(np.isin(gear,[1,2,3,4]).all()),
        GearRho=float(min((gear-1).min(),(4-gear).min())),
        FirstReachSeconds=float(data['TimeSeconds'][reach[0]]) if len(reach) else float('nan'))
