---
name: mlflow-analyzer
description: |
  Analyze MLflow classification experiments to identify best-performing feature sets and models.
  Use when user asks to: analyze MLflow results, compare features, find best models, get experiment
  conclusions, review classification performance, identify winning feature combinations, compare
  feature importance across runs, or generate experiment reports.
---

# MLflow Experiment Analyzer

Analyze classification experiments from MLflow to identify best feature sets, rank models by F1 score, and generate insights.

## Quick Start

```bash
# Fetch results from MLflow
python scripts/fetch_mlflow_results.py <experiment_name> -o results.json

# Analyze and generate report
python scripts/analyze_results.py results.json --top-n 10
```

## Workflow

### 1. Fetch Experiment Data

```bash
python scripts/fetch_mlflow_results.py <experiment_name> \
  --host http://127.0.0.1 \
  --port 8081 \
  -o results.json
```

**Filtering options:**
- `--status FINISHED` - Only completed runs
- `--start-date 2024-01-01` - Runs after date
- `--end-date 2024-12-31` - Runs before date
- `--filter "params.config.model.class_name = 'random_forest'"` - MLflow filter syntax
- `--download-artifacts` - Download SHAP/permutation importance HTML files

### 2. Analyze Results

```bash
# Markdown report (default)
python scripts/analyze_results.py results.json --top-n 10

# JSON output
python scripts/analyze_results.py results.json --format json

# Compare two feature sets statistically
python scripts/analyze_results.py results.json --compare "featureA|featureB" "featureC|featureD"
```

## Output Formats

**Markdown report includes:**
- Top N runs ranked by total F1 score
- Feature frequency analysis (which features appear in top runs)
- Per-class performance summary (mean, std, min, max F1)
- Recommendations based on analysis

**Statistical comparison:**
- Mann-Whitney U test for comparing feature sets
- Reports p-value and significance at α=0.05

## Classes Tracked

- `bird`, `multi_rotor_drone`, `fixed_wing_drone`, `airplane`, `total`

## Metric Interpretation

See [references/metrics.md](references/metrics.md) for metric definitions and statistical test interpretation.

## Example Analysis Prompt

> "Analyze my 'classification' experiment and tell me which features work best"

Response workflow:
1. Run fetch script to get results.json
2. Run analyze script with --top-n 10
3. Present markdown report with rankings, feature frequency, and recommendations
