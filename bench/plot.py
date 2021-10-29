#!/usr/bin/env python3

# import matplotlib._color_data as mcd
import matplotlib.pyplot as plt
import pandas as pd
import sys

data_sets = [pd.read_csv(file) for file in sys.argv[1:]]
for data_set in data_sets:
  print(data_set)

prefixes = ['requests', 'latency']

y_axes = {
  'requests': 'requests/s',
  'latency': 'latency (ms)',
}

fig, axes = plt.subplots(len(prefixes))
if isinstance(axes, plt.Axes):
  axes = [axes]

for axis, prefix in zip(axes, prefixes):
  axis.set(xlabel = 'connections', ylabel = y_axes[prefix])
  axis.label_outer()
  axis.margins(x=0.015)

  for data_set in data_sets:
    x = data_set['connections']
    y = data_set[f"{prefix}_avg"]
    label = data_set['label'].iloc[0]
    y_err = [y - data_set[f"{prefix}_min"], data_set[f"{prefix}_max"] - y]
    axis.errorbar(x, y, y_err, label = label, capsize = 5.0, elinewidth = 0.5)

  axis.legend()

plt.tight_layout()
plt.show()
