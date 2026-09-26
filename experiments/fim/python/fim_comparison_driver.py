"""FIM-only adapter around Falsify's actual driver/ChainerRL agent factories.

The public driver.py is not edited. Correct episode alignment is enforced by
fim_comparison_agent: 6 applied actions, 6 transitions, no unused t=30 action.
ACER retains 10000 transitions; all other factory hyperparameters are retained.
"""
import array
import json
import numpy as np
import driver
from chainerrl.replay_buffer import EpisodicReplayBuffer

_original_start = driver.start_learning
_original_stop = driver.stop_episode_and_train
_current = []
_episodes = 0
_transitions = 0
_online_updates = 0
_replay_updates = 0
_algorithm = None
_capacity = 10000


def install(capacity=10000):
    global _capacity
    _capacity = int(capacity)
    driver.start_learning = start_learning
    driver.stop_episode_and_train = finish_episode


def start_learning(algorithm, observation_dim, action_dim, alpha):
    global _current, _episodes, _transitions, _online_updates, _replay_updates, _algorithm
    _original_start(algorithm, observation_dim, action_dim, alpha)
    _current, _episodes, _transitions = [], 0, 0
    _online_updates = _replay_updates = 0
    _algorithm = str(algorithm)
    if algorithm == "ACER":
        driver.agent.replay_buffer = EpisodicReplayBuffer(_capacity)
        original_update = driver.agent.update

        def counted_update(*args, **kwargs):
            global _online_updates, _replay_updates
            before = driver.agent.optimizer.t
            result = original_update(*args, **kwargs)
            difference = driver.agent.optimizer.t - before
            if kwargs.get("action_distribs_mu") is None:
                _online_updates += difference
            else:
                _replay_updates += difference
            return result

        driver.agent.update = counted_update


def action(state, time_seconds):
    global _transitions
    t = float(time_seconds)
    assert t == 5 * len(_current) and 0 <= t < 30, (t, len(_current))
    state = np.asarray(state, dtype=np.float32).reshape(-1)
    applied = driver.driver(state, 0.0)
    if _current:
        _transitions += 1
    _current.append({"Time": t, "Action": float(applied[0]), "State": state.tolist()})
    return array.array("d", applied)


def finish_episode(state, reward):
    global _episodes, _transitions, _current
    assert len(_current) == 6, "Exactly six applied actions must precede terminal training"
    state = np.asarray(state, dtype=np.float32).reshape(-1)
    if _algorithm == "RAND":
        _original_stop(state, float(reward))
    else:
        driver.agent.stop_episode_and_train(state, float(reward), done=True)
    _transitions += 1
    _episodes += 1
    assert _transitions == 6 * _episodes
    _current = []


def episode_json():
    return json.dumps(_current)


def stats_json():
    agent = driver.agent
    return json.dumps({
        "Algorithm": _algorithm, "CompletedEpisodes": _episodes,
        "Transitions": _transitions, "CurrentActions": len(_current),
        "OptimizerUpdates": int(agent.optimizer.t) if hasattr(agent, "optimizer") else 0,
        "ACEROnlineUpdates": _online_updates, "ACERReplayUpdates": _replay_updates,
        "ReplaySize": len(agent.replay_buffer) if hasattr(agent, "replay_buffer") else 0,
    })
