#!/usr/bin/env python3
"""
Patch selkies so the GPU statistics query cannot freeze the stream.

ROOT CAUSE:
-----------
selkies fills the dashboard's GPU gauge with GPUtil.getGPUs(), which runs
`nvidia-smi --query-gpu=...` and waits for its output. The call sits directly
in the asyncio event loop: once per second in _collect_gpu_stats_ws() and once
when a client connects (ws_handler). The same loop sends every video and audio
chunk and handles all input.

On native Linux nvidia-smi answers in a few tens of milliseconds. On WSL2 it
takes about 3 seconds, so the event loop was blocked in read() on the
nvidia-smi pipe most of the time: capture and NVENC kept running at full rate,
but nothing was sent for 1-5 seconds, then the queued frames went out in a
burst. On the desktop this looked like the picture and the pointer freezing
for seconds, on every NVIDIA WSL session, regardless of GPU load.

Moving the call off the loop is not enough on WSL2. While nvidia-smi runs,
the Windows host makes every other process's GPU calls wait: texture and
buffer creation (D3DKMTCreateAllocation2) and NVENC's completion wait
(D3DKMTWaitForSynchronizationObjectFromCpu) took 0.2-3.7 s instead of about
1 ms. A 256x256 texture creation was measured at up to 2.7 s, and every stall
above 0.5 s coincided with a running nvidia-smi. selkies starts one monitor
per connected client, so nvidia-smi ran about 1.6 times per second and KWin
(new windows, screencast buffers) and pixelflux froze for seconds at random.

FIX:
----
1. WSL2 (WSL_ENVIRONMENT=true): do not start the GPU monitor at all. The only
   thing lost is the GPU load gauge in the dashboard. SELKIES_GPU_STATS=true
   turns it back on (queried at most every 10 s), =false forces it off
   everywhere.
2. Elsewhere: run GPUtil.getGPUs() in a worker thread (asyncio.to_thread) so
   the event loop keeps sending while nvidia-smi runs, and wait at least
   three times as long as the last query took (capped at 10 s).
"""

import glob
import os
import sys

MARKER = "# gpu-stats-off-loop"


def find_selkies_py():
    for path in glob.glob("/opt/selkies-env/lib/python*/site-packages/selkies/selkies.py"):
        if os.path.isfile(path):
            return path
    return None


def replace_exact(content, name, old, new, expected):
    count = content.count(old)
    if count != expected:
        raise SystemExit(
            f"patch-selkies-gpu-stats: {name}: expected {expected} occurrence(s), found {count}"
        )
    print(f"  [OK] {name}")
    return content.replace(old, new)


def main():
    path = find_selkies_py()
    if not path:
        print("patch-selkies-gpu-stats: selkies.py not found; skipping")
        return
    with open(path, encoding="utf-8") as f:
        content = f.read()
    if MARKER in content:
        print(f"patch-selkies-gpu-stats: already patched: {path}")
        return
    if "GPUtil.getGPUs()" not in content:
        print("patch-selkies-gpu-stats: GPUtil.getGPUs() not used; nothing to patch")
        return

    print(f"patch-selkies-gpu-stats: patching {path}")

    # Client connect: decide whether to start the GPU monitor.
    content = replace_exact(
        content,
        "connect-time GPU probe",
        "        if GPUtil.getGPUs():\n"
        "            self._gpu_monitor_task_ws = asyncio.create_task(\n",
        f"        if _selkies_gpu_stats_enabled() and await asyncio.to_thread(GPUtil.getGPUs):  {MARKER}\n"
        "            self._gpu_monitor_task_ws = asyncio.create_task(\n",
        1,
    )

    # Monitor start-up probe.
    content = replace_exact(
        content,
        "monitor start-up probe",
        "    try:\n"
        "        gpus = GPUtil.getGPUs()\n"
        "        if not gpus:\n"
        '            data_logger.warning("No GPUs detected for GPU monitor (WS).")\n',
        "    try:\n"
        f"        gpus = await asyncio.to_thread(GPUtil.getGPUs)  {MARKER}\n"
        "        _gpu_query_s = 0.0\n"
        "        if not gpus:\n"
        '            data_logger.warning("No GPUs detected for GPU monitor (WS).")\n',
        1,
    )

    # Periodic query.
    content = replace_exact(
        content,
        "periodic query",
        "            try:\n"
        "                gpus = GPUtil.getGPUs()\n"
        "                if not gpus or gpu_id >= len(gpus):\n",
        "            try:\n"
        "                _gpu_query_t0 = time.monotonic()\n"
        f"                gpus = await asyncio.to_thread(GPUtil.getGPUs)  {MARKER}\n"
        "                _gpu_query_s = time.monotonic() - _gpu_query_t0\n"
        "                if not gpus or gpu_id >= len(gpus):\n",
        1,
    )

    # Pace by the cost of the query.
    content = replace_exact(
        content,
        "query pacing",
        "                await asyncio.sleep(interval_seconds * 2)\n"
        "            await asyncio.sleep(interval_seconds)\n"
        "    except asyncio.CancelledError:\n"
        '        data_logger.info("GPU monitor (WS) cancelled.")\n',
        "                await asyncio.sleep(interval_seconds * 2)\n"
        "            await asyncio.sleep(max(interval_seconds, _SELKIES_GPU_STATS_MIN_INTERVAL, min(10.0, _gpu_query_s * 3)))\n"
        "    except asyncio.CancelledError:\n"
        '        data_logger.info("GPU monitor (WS) cancelled.")\n',
        1,
    )

    # Policy helper, placed in front of the monitor coroutine.
    content = replace_exact(
        content,
        "policy helper",
        "async def _collect_gpu_stats_ws(shared_data, gpu_id=0, interval_seconds=1):\n",
        "def _selkies_gpu_stats_enabled():\n"
        '    value = os.environ.get("SELKIES_GPU_STATS", "").strip().lower()\n'
        '    if value in ("1", "true", "yes", "on"):\n'
        "        return True\n"
        '    if value in ("0", "false", "no", "off"):\n'
        "        return False\n"
        "    # nvidia-smi stalls every GPU call of every process on WSL2.\n"
        '    return os.environ.get("WSL_ENVIRONMENT", "").strip().lower() != "true"\n'
        "\n"
        "\n"
        "_SELKIES_GPU_STATS_MIN_INTERVAL = (\n"
        '    10.0 if os.environ.get("WSL_ENVIRONMENT", "").strip().lower() == "true" else 0.0\n'
        ")\n"
        "\n"
        "\n"
        "async def _collect_gpu_stats_ws(shared_data, gpu_id=0, interval_seconds=1):\n",
        1,
    )

    if "\nimport os\n" not in content:
        raise SystemExit("patch-selkies-gpu-stats: selkies.py does not import os")
    if "\nimport time\n" not in content and "\nimport time " not in content:
        raise SystemExit("patch-selkies-gpu-stats: selkies.py does not import time")

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    for pyc in glob.glob(os.path.join(os.path.dirname(path), "__pycache__", "selkies.*.pyc")):
        os.remove(pyc)
    print("patch-selkies-gpu-stats: done")


if __name__ == "__main__":
    sys.exit(main())
