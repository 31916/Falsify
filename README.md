# Falsification of Cyber Physical Systems by Deep Reinforcement Learning

## What is this?

This package is to evaluate deep reinforcement learning technology for falsification of cyber-physical systems. It contains four models (an auto-transmission model, a wind turbine model, a power train control model and an insulin model. The insulin model currently does not work.

## Audience

This package is for researchers and developers who evaluates the technology.

## Reqiurment

- MATLAB
- Simulink
- Stateflow
- Decent distribution of Python
- ChainerRL 0.2.0
- s-taliro
- breach


## Agenda

- metascript.m : scripts for AT and PTC model. An insulin model is included but not working.
- metascript_cars.m : a script for CARS model
- metascript_wind_turbine.m : a script for the wind turbine model.

## ARCH-COMP 2025 validation

This branch adds a unified Falsify-to-official-model validation pipeline for SB, AT, AFC, CC, NN, F16, and SC. It runs RAND, A3C, ACER, and DDQN for one episode per applicable benchmark condition, validates the generated input, replays the same input on the official model, and records official STL robustness and classification agreement.

The local validation result is 188/188 completed cases, including 27 candidates whose official robustness is negative. This is an integration run, not an algorithm-performance comparison. See [ARCH_COMP_2025.md](ARCH_COMP_2025.md) for setup, commands, scope, results, and the trajectory-equivalence caveat.


## License
(C) 2019 National Institute of Advanced Industrial Science and Technology (AIST)

The contents under the wind-turbine directory is copyrighted by the respective authors.

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.                                    

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.                           

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA


## Usage
Edit the section named "Configuration" and run the script
