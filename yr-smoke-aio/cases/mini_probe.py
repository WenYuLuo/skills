# Minimal cluster probe: init via in-cluster gRPC, run an actor, read multi-node resources().
# Usage (inside master): YR_TEST_CONFIG_FILE=/root/.yr/config.ini python3 mini_probe.py
import os, configparser, yr
cf = configparser.ConfigParser(); cf.read(os.environ.get("YR_TEST_CONFIG_FILE", "/root/.yr/config.ini"))
s = cf["python"]
yr.init(yr.Config(server_address=s["server_address"], ds_address=s["datasystem_address"],
                  in_cluster=s.get("in_cluster", "true").strip().lower() == "true",
                  master_addr_list=[s["master_addr"]]))
@yr.instance
class Counter:
    def __init__(self): self.n = 0
    def inc(self): self.n += 1; return self.n
print("ACTOR_INC:", yr.get(Counter.invoke().inc.invoke()))
r = yr.resources()
print("NODE_COUNT:", len(r) if r else 0)
yr.finalize()
print("MINI_PROBE_DONE")
