"""Test bounded actions and real weight updates, independently of AT results."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

import numpy as np

import driver


def check_algorithm(algorithm, episodes):
    random.seed(101)
    np.random.seed(101)
    driver.start_learning(algorithm, 3, 2, 0)
    driver.act(np.zeros(3, dtype=np.float32))
    before = {
        name: parameter.array.copy()
        for name, parameter in driver.agent.model.namedparams()
        if parameter.array is not None
    }
    for episode in range(episodes):
        for step in range(7):
            state = np.array([step / 7, episode / episodes, -0.5], dtype=np.float32)
            action = np.asarray(driver.driver(state, 0.1))
            assert action.shape == (2,)
            assert np.isfinite(action).all() and (np.abs(action) <= 1).all()
        driver.stop_episode_and_train(state, 0.2)
        if algorithm == "DDQN" and episode == 9:
            assert driver.agent.optimizer.t == 0, "DDQN unexpectedly trained before warmup"
    changed = 0
    for name, parameter in driver.agent.model.namedparams():
        assert parameter.array is not None and np.isfinite(parameter.array).all()
        if name in before and not np.array_equal(parameter.array, before[name]):
            changed += 1
    assert changed > 0, f"{algorithm} ran without updating its parameters"
    assert driver.agent.optimizer.t > 0
    print(f"PASS: {algorithm}: {changed} parameter arrays changed, "
          f"{driver.agent.optimizer.t} optimizer updates over {episodes} synthetic episodes.")


def main():
    for algorithm, episodes in [("ACER", 3), ("A3C", 3), ("DDQN", 80)]:
        check_algorithm(algorithm, episodes)
    assert np.__config__.get_info("openblas64__info"), "Unexpected NumPy BLAS build"
    print(f"NumPy {np.__version__}; installed build uses OpenBLAS ILP64.")


if __name__ == "__main__":
    main()
