# Classification Experiment Analysis

Use this when MLflow runs represent classifier training/evaluation results.

## Expected Run Shape

The bundled scripts support this schema by default:

- Feature set parameter: `config.data.features_to_use`
- Per-class F1 metric: `{class_name}.f1_score.test`
- Other metric template: `{class_name}.{metric}.test`
- Default classes: `bird`, `multi_rotor_drone`, `fixed_wing_drone`, `airplane`, `total`
- Primary metric class: `total`

Override these assumptions with script flags instead of editing code:

```bash
python scripts/fetch_mlflow_results.py <experiment> \
  --feature-param config.data.features_to_use \
  --classes bird,multi_rotor_drone,fixed_wing_drone,airplane,total \
  --f1-metric-template '{class_name}.f1_score.test'

python scripts/analyze_results.py results.json \
  --metric total \
  --feature-field features_used
```

## Analysis Questions

- Which runs rank highest by the primary metric?
- Which feature sets appear most often among top runs?
- Which classes are hardest by mean F1?
- Are competing feature sets supported by enough samples for comparison?
- Are improvements practically meaningful, not just statistically significant?

## Statistical Comparisons

The analyzer uses Mann-Whitney U for two independent samples.

Treat results as directional when:

- either group has fewer than 5 runs
- runs are not independent
- feature sets differ alongside model/hyperparameter changes
- p-value is significant but effect size is tiny

Always report sample sizes and means alongside p-values.
