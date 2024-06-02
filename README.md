# Intellij Custom Profile

This modified script is designed to launch IntelliJ while limiting the system resources allocated to that process. The tools utilized are native to Linux and operate at the kernel and system level. Given that IntelliJ consumes significant resources, the aim is to prevent RAM saturation and ensure CPU stability even during heavy load scenarios.

This script relies on `systemd-run` (for direct memory management) and `taskset` (for direct affinity management).

How to use
---

Put the script in the bin folder of IntelliJ (where the original idea.sh script is located) and run this instead of the original.

```sh
env PARAM=val ./idea_mod.sh
```

| Env | Value | Description |
|:---:|:-----:|:-----------:|
| RAM_LIMIT | sizeG or M | Max RAM limit allowed |
| CPU_SET_ARGS | core list like: 1,2,3,4 | force CPU core to use |
