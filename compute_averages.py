#!/usr/bin/env python3
"""Compute averages of tookMs for each heap+graph combination from results.csv.

Usage:
    python compute_averages.py

Outputs CSV lines: heap,graph,average_tookMs
"""
import csv
from collections import defaultdict


def compute_averages(path="results.csv"):
    sums = defaultdict(float)
    counts = defaultdict(int)
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            heap = row.get('heap')
            graph = row.get('graph')
            if not heap or not graph:
                continue
            try:
                val = float(row.get('tookMs', ''))
            except Exception:
                continue
            key = (heap.strip(), graph.strip())
            sums[key] += val
            counts[key] += 1

    results = {}
    for key in sorted(sums.keys()):
        if counts[key]:
            results[key] = sums[key] / counts[key]
        else:
            results[key] = None
    return results


def main():
    results = compute_averages()
    # Print header
    print('heap,graph,average_tookMs')
    # Ensure stable ordering
    for heap in ['binary', 'fibonacci']:
        for graph in ['array', 'linked']:
            avg = results.get((heap, graph))
            if avg is None:
                print(f'{heap},{graph},')
            else:
                print(f'{heap},{graph},{avg:.6f}')


if __name__ == '__main__':
    main()
