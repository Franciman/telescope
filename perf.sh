#!/bin/sh

perf stat -B -e task-clock,context-switches,page-faults,cycles,instructions,branches,branch-misses,cache-references,cache-misses zig-out/bin/telescope
