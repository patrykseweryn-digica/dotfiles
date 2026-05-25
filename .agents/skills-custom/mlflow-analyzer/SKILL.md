---
name: mlflow-analyzer
description: "Analyze traditional MLflow experiment runs, rankings, metrics, feature sets, and model candidates."
argument-hint: "[experiment name or fetched-results.json]"
---

# MLflow Analyzer

Analyze traditional MLflow experiment runs. This skill is for training/evaluation runs, not GenAI traces.

## Use When

- User asks which model, run, feature set, or hyperparameter setup performed best.
- User wants a report from existing MLflow runs.
- User wants classification experiment analysis: F1, per-class metrics, feature frequency, statistical comparison.

For GenAI traces, sessions, token usage, or agent quality, use the tracing/evaluation MLflow skills instead.

## Workflow

1. Classify the analysis target:
   - Existing fetched JSON: run `scripts/analyze_results.py` directly.
   - MLflow experiment name/id: fetch first with `scripts/fetch_mlflow_results.py`.
   - Classification metrics/feature sets: read `references/classification.md`.
   - Metric definitions/statistical interpretation: read `references/metrics.md`.
2. Fetch runs when needed:
   ```bash
   python scripts/fetch_mlflow_results.py <experiment-name> -o results.json
   python scripts/fetch_mlflow_results.py --experiment-id <id> -o results.json
   ```
3. Analyze:
   ```bash
   python scripts/analyze_results.py results.json --top-n 10
   python scripts/analyze_results.py results.json --format json
   python scripts/analyze_results.py results.json --compare "featureA|featureB" "featureC|featureD"
   ```
4. Report rankings, metric caveats, feature-set evidence, sample sizes, and next experiment recommendations.

## Boundaries

- Do not use this for MLflow trace/session debugging.
- Do not overstate statistical comparisons with small sample sizes.
- Do not assume the drone/bird class schema unless the run metrics match it or the user asks for that project-specific analysis.
- Prefer configurable script flags over editing scripts for one-off experiments.
