#!/usr/bin/env python3
# Copyright 2026 HTCondor Team, Computer Sciences Department,
# University of Wisconsin-Madison, WI.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Wrapper around condor_adstash that saves and loads checkpoints to/from
Elasticsearch instead of from disk.

If ADSTASH_CHECKPOINT_INDEX is not set, this script exec()s condor_adstash
directly (pass-through mode) to preserve existing behavior.

If ADSTASH_CHECKPOINT_INDEX is set, the behavior is:
  1. Load checkpoint JSON from ES index and write it to checkpoint file path
  2. Run condor_adstash as a subprocess with original args/config
  3. Read updated checkpoint file and save ir to ES
  4. Exit with condor_adstash's return code
"""

import os
import sys
import json
import time
import logging
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ADSTASH_BIN = os.environ["ADSTASH_BIN"]
ADSTASH_CHECKPOINT_INDEX = os.environ.get("ADSTASH_CHECKPOINT_INDEX")

# If no checkpoint index set, replace this script with condor_adstash itself
if not ADSTASH_CHECKPOINT_INDEX:
    os.execv(
        f"{ADSTASH_BIN}/condor_adstash",
        ["condor_adstash"] + sys.argv[1:],
    )

# Use ES-backed checkpointing
from adstash.config import get_config
from adstash.interfaces.elasticsearch import ElasticsearchInterface
import elasticsearch


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [checkpoint_wrapper] %(levelname)s %(message)s",
    )

    # Use the same config parsing as adstash
    args = get_config()
    checkpoint_file = Path(args.checkpoint_file)

    if ADSTASH_CHECKPOINT_INDEX == args.se_index_name:
        logging.critical(
            f"ADSTASH_CHECKPOINT_INDEX '{ADSTASH_CHECKPOINT_INDEX}' is the same as "
            f"the adstash target index. Checkpoint docs and adstash docs must not share "
            f"an index. Set ADSTASH_CHECKPOINT_INDEX to a different value and restart."
        )
        sys.exit(1)

    # Use the adstash ElasticsearchInterface to build ES client
    iface = ElasticsearchInterface(
        host=args.se_host,
        url_prefix=getattr(args, "se_url_prefix", ""),
        username=args.se_username,
        password=args.se_password,
        use_https=args.se_use_https,
        ca_certs=args.se_ca_certs,
        timeout=args.se_timeout,
    )
    client = iface.get_handle()

    # LOAD CHECKPOINT
    # fetch latest checkpoint from ES, write to checkpoint_file
    try:
        resp = client.get(index=ADSTASH_CHECKPOINT_INDEX, id="latest")
        checkpoint_file.write_text(json.dumps(resp["_source"]["checkpoint"]))
        logging.info(f"Loaded checkpoint from index '{ADSTASH_CHECKPOINT_INDEX}'")
    except elasticsearch.NotFoundError:
        if checkpoint_file.exists():
            logging.info(
                f"No checkpoint found in index '{ADSTASH_CHECKPOINT_INDEX}', "
                f"using existing checkpoint file at '{checkpoint_file}'"
            )
        else:
            logging.info(
                f"No checkpoint found in index '{ADSTASH_CHECKPOINT_INDEX}', starting fresh"
            )
            checkpoint_file.write_text("{}")
    except Exception as e:
        if checkpoint_file.exists():
            logging.warning(
                f"Could not load checkpoint from ES: {e}, "
                f"using existing checkpoint file at '{checkpoint_file}'"
            )
        else:
            logging.warning(
                f"Could not load checkpoint from ES: {e}, starting fresh"
            )
            checkpoint_file.write_text("{}")

    # RUN condor_adstash
    # subprocess.run() with no stdout/stderr flags inherits the wrapper's file descriptors
    result = subprocess.run(
        [f"{ADSTASH_BIN}/condor_adstash"] + sys.argv[1:],
        env=os.environ,
    )

    # SAVE CHECKPOINT
    # write the checkpoint file back to ES, both to latest and timestamped docs
    try:
        checkpoint_data = json.loads(checkpoint_file.read_text())
        now = datetime.now(timezone.utc).isoformat()
        doc = {"@timestamp": now, "checkpoint": checkpoint_data}
        client.index(index=ADSTASH_CHECKPOINT_INDEX, id="latest", document=doc)
        client.index(
            index=ADSTASH_CHECKPOINT_INDEX,
            id=f"checkpoint-{int(time.time())}",
            document=doc,
        )
        logging.info(f"Saved checkpoint to index '{ADSTASH_CHECKPOINT_INDEX}'")
    except Exception as e:
        logging.error(f"Could not save checkpoint to ES: {e}")

    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
