"""Detach an already validated campaign and prevent idle sleep while it runs."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from run_torque_campaign import REPO, check_frozen, environment, run, write_json
from summarize_torque_campaign import summarize


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign',type=Path)
    parser.add_argument('--worker',action='store_true')
    args=parser.parse_args(); campaign=args.campaign.resolve()
    check_frozen(campaign)
    assert json.loads((campaign/'preflight.json').read_text())['Status']=='PASS'
    if not args.worker:
        with (campaign/'campaign.log').open('x') as log:
            process=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),str(campaign),'--worker'],
                cwd=REPO,env=environment(),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        receipt=dict(PID=process.pid,Campaign=str(campaign),Log=str(campaign/'campaign.log'),
                     LauncherSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
        write_json(campaign/'launch.json',receipt)
        print(json.dumps(receipt,indent=2)); return
    # A held OS lock, not just a stale PID file, prevents duplicate workers.
    with (REPO/'results/fim/experiment-worker.lock').open('a') as lock:
        fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        # Ends with this worker. Does not block manual sleep or closed-lid sleep.
        awake=subprocess.Popen(['/usr/bin/caffeinate','-i','-w',str(os.getpid())])
        try:
            run(campaign)
            summarize(campaign)
        except Exception as error:
            write_json(campaign/'status.json',dict(Status='error',Stage='formal campaign',
                       Error=str(error),PID=os.getpid()))
            raise
        finally:
            awake.terminate()


if __name__=='__main__':
    main()
