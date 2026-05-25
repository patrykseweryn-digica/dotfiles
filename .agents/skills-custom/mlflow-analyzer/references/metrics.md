# Classification Metrics Reference

## Primary Metrics

### F1 Score
Harmonic mean of precision and recall. Best single metric for imbalanced classes.
- Range: 0-1 (higher is better)
- F1 = 2 * (precision * recall) / (precision + recall)
- Use when false positives and false negatives have similar cost

### Precision
Fraction of predicted positives that are actually positive.
- High precision = few false positives
- Important when false positives are costly

### Recall (Sensitivity)
Fraction of actual positives correctly identified.
- High recall = few false negatives
- Important when missing positives is costly

### ROC-AUC
Area under ROC curve. Measures discrimination ability across thresholds.
- Range: 0.5 (random) to 1.0 (perfect)
- Threshold-independent

### Balanced Accuracy
Average of recall for each class. Handles imbalanced datasets.
- Range: 0-1
- Better than accuracy for imbalanced data

## Statistical Tests

### Mann-Whitney U Test
Non-parametric test comparing two independent samples.
- p < 0.05: statistically significant difference
- Used when comparing feature sets with different runs

### Interpretation
- p < 0.001: Very strong evidence
- p < 0.01: Strong evidence
- p < 0.05: Moderate evidence
- p >= 0.05: Insufficient evidence

## Default Project Classes

| Class | Description |
|-------|-------------|
| bird | Bird targets |
| multi_rotor_drone | Multi-rotor UAVs |
| fixed_wing_drone | Fixed-wing UAVs |
| airplane | Conventional aircraft |
| total | Aggregate across all classes |

These are defaults for the historical drone/bird classification project. Override them with `--classes` for other classifiers.

## Feature Importance Types

### Built-in Importance
Model-specific (e.g., Gini importance for Random Forest). Fast but can be biased.

### Permutation Importance
Measures F1 drop when feature values are shuffled. More reliable than built-in.

### SHAP Values
Game-theoretic approach. Shows both magnitude and direction of feature effects.
