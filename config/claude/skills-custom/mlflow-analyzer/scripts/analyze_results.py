#!/usr/bin/env python3
"""Analyze MLflow experiment results: rankings, feature analysis, statistical comparisons."""

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats


@dataclass
class ExperimentAnalyzer:
    """Analyze MLflow experiment results for feature insights."""

    data: list[dict]
    primary_metric: str = "total"
    top_n: int = 10
    classes_of_interest: list[str] = field(
        default_factory=lambda: [
            "bird",
            "multi_rotor_drone",
            "fixed_wing_drone",
            "airplane",
            "total",
        ]
    )

    def get_rankings(self) -> pd.DataFrame:
        """Rank runs by primary metric F1 score."""
        rows = []
        for item in self.data:
            f1 = item["f1_scores"].get(self.primary_metric)
            if f1 is None:
                continue
            rows.append({
                "run_name": item["run_name"],
                "features": item["features_used"],
                f"{self.primary_metric}_f1": f1,
                **{f"{k}_f1": v for k, v in item["f1_scores"].items() if k != self.primary_metric and v is not None},
            })

        df = pd.DataFrame(rows)
        if not df.empty:
            df = df.sort_values(f"{self.primary_metric}_f1", ascending=False).reset_index(drop=True)
            df.index += 1
        return df

    def get_top_runs(self, n: int | None = None) -> list[dict]:
        """Get top N runs by primary metric."""
        n = n or self.top_n
        sorted_data = sorted(
            [d for d in self.data if d["f1_scores"].get(self.primary_metric) is not None],
            key=lambda x: x["f1_scores"][self.primary_metric],
            reverse=True,
        )
        return sorted_data[:n]

    def _parse_features(self, features_str: str) -> list[str]:
        """Parse feature string into list of feature names."""
        # Handle Python list string format: "['a', 'b', 'c']"
        if features_str.startswith("[") and features_str.endswith("]"):
            import ast
            try:
                return ast.literal_eval(features_str)
            except (ValueError, SyntaxError):
                pass
        # Handle pipe-separated format: "a|b|c"
        if "|" in features_str:
            return [f.strip() for f in features_str.split("|")]
        # Handle comma-separated format: "a, b, c"
        if "," in features_str:
            return [f.strip() for f in features_str.split(",")]
        return [features_str.strip()]

    def analyze_feature_frequency(self, n: int | None = None) -> dict:
        """Analyze feature frequency in top N runs."""
        top_runs = self.get_top_runs(n)
        all_features: list[str] = []

        for run in top_runs:
            features_str = run["features_used"]
            if features_str:
                features = self._parse_features(features_str)
                all_features.extend(features)

        frequency = Counter(all_features)
        total_runs = len(top_runs)

        return {
            "feature_counts": dict(frequency.most_common()),
            "feature_percentages": {k: v / total_runs * 100 for k, v in frequency.items()},
            "total_runs_analyzed": total_runs,
        }

    def compare_feature_sets(
        self, feature_set_a: str, feature_set_b: str, metric: str = "total"
    ) -> dict:
        """Statistical comparison between two feature sets using Wilcoxon test."""
        runs_a = [d for d in self.data if d["features_used"] == feature_set_a]
        runs_b = [d for d in self.data if d["features_used"] == feature_set_b]

        if not runs_a or not runs_b:
            return {"error": "One or both feature sets not found"}

        scores_a = [r["f1_scores"].get(metric) for r in runs_a if r["f1_scores"].get(metric) is not None]
        scores_b = [r["f1_scores"].get(metric) for r in runs_b if r["f1_scores"].get(metric) is not None]

        if len(scores_a) < 2 or len(scores_b) < 2:
            return {
                "mean_a": np.mean(scores_a) if scores_a else None,
                "mean_b": np.mean(scores_b) if scores_b else None,
                "note": "Insufficient samples for statistical test",
            }

        # Mann-Whitney U test (non-parametric, unpaired)
        try:
            stat, p_value = stats.mannwhitneyu(scores_a, scores_b, alternative="two-sided")
        except Exception:
            stat, p_value = None, None

        return {
            "feature_set_a": feature_set_a,
            "feature_set_b": feature_set_b,
            "metric": metric,
            "mean_a": np.mean(scores_a),
            "std_a": np.std(scores_a),
            "n_a": len(scores_a),
            "mean_b": np.mean(scores_b),
            "std_b": np.std(scores_b),
            "n_b": len(scores_b),
            "mann_whitney_stat": stat,
            "p_value": p_value,
            "significant_at_005": p_value < 0.05 if p_value is not None else None,
        }

    def get_per_class_summary(self) -> pd.DataFrame:
        """Summary statistics per class across all runs."""
        results = []
        for class_name in self.classes_of_interest:
            scores = [
                d["f1_scores"].get(class_name)
                for d in self.data
                if d["f1_scores"].get(class_name) is not None
            ]
            if scores:
                results.append({
                    "class": class_name,
                    "mean_f1": np.mean(scores),
                    "std_f1": np.std(scores),
                    "min_f1": np.min(scores),
                    "max_f1": np.max(scores),
                    "n_runs": len(scores),
                })

        return pd.DataFrame(results)

    def generate_recommendations(self, top_n: int = 5) -> list[str]:
        """Generate actionable recommendations based on analysis."""
        recommendations = []

        # Get top runs
        top_runs = self.get_top_runs(top_n)
        if not top_runs:
            return ["No runs found with valid metrics."]

        # Best model info
        best = top_runs[0]
        best_f1 = best["f1_scores"].get(self.primary_metric)
        recommendations.append(
            f"Best model achieves {self.primary_metric} F1 of {best_f1:.4f} using features: {best['features_used']}"
        )

        # Feature frequency insight
        freq = self.analyze_feature_frequency(top_n)
        if freq["feature_counts"]:
            top_features = list(freq["feature_counts"].keys())[:3]
            recommendations.append(
                f"Most frequent features in top {top_n} runs: {', '.join(top_features)}"
            )

        # Per-class insights
        class_summary = self.get_per_class_summary()
        if not class_summary.empty:
            # Find hardest class (excluding 'total')
            non_total = class_summary[class_summary["class"] != "total"]
            if len(non_total) > 0:
                hardest_idx = non_total["mean_f1"].idxmin()
                hardest = non_total.loc[hardest_idx]
                recommendations.append(
                    f"Hardest class to classify: {hardest['class']} (mean F1: {hardest['mean_f1']:.4f})"
                )

        return recommendations

    def to_markdown_report(self, top_n: int = 10) -> str:
        """Generate full markdown analysis report."""
        lines = ["# MLflow Experiment Analysis Report\n"]

        # Rankings
        lines.append("## Top Runs by F1 Score\n")
        rankings = self.get_rankings().head(top_n)
        if not rankings.empty:
            lines.append(rankings.to_markdown(index=True))
        lines.append("\n")

        # Feature frequency
        lines.append("## Feature Frequency in Top Runs\n")
        freq = self.analyze_feature_frequency(top_n)
        for feature, count in freq["feature_counts"].items():
            pct = freq["feature_percentages"][feature]
            lines.append(f"- **{feature}**: {count}/{freq['total_runs_analyzed']} runs ({pct:.0f}%)")
        lines.append("\n")

        # Per-class summary
        lines.append("## Per-Class Performance Summary\n")
        class_summary = self.get_per_class_summary()
        if not class_summary.empty:
            lines.append(class_summary.to_markdown(index=False))
        lines.append("\n")

        # Recommendations
        lines.append("## Recommendations\n")
        for rec in self.generate_recommendations(top_n):
            lines.append(f"- {rec}")
        lines.append("\n")

        return "\n".join(lines)


def parse_args():
    parser = argparse.ArgumentParser(description="Analyze MLflow experiment results")
    parser.add_argument("input", help="JSON file with fetched results (from fetch_mlflow_results.py)")
    parser.add_argument("--top-n", type=int, default=10, help="Number of top runs to analyze")
    parser.add_argument("--metric", default="total", help="Primary metric class (default: total)")
    parser.add_argument("--output", "-o", help="Output file path")
    parser.add_argument("--format", choices=["markdown", "json", "table"], default="markdown")
    parser.add_argument("--compare", nargs=2, metavar=("SET_A", "SET_B"), help="Compare two feature sets")
    return parser.parse_args()


def main():
    args = parse_args()

    # Load data
    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    with open(input_path) as f:
        data = json.load(f)

    analyzer = ExperimentAnalyzer(data=data, primary_metric=args.metric, top_n=args.top_n)

    # Statistical comparison if requested
    if args.compare:
        result = analyzer.compare_feature_sets(args.compare[0], args.compare[1], args.metric)
        output = json.dumps(result, indent=2, default=str)
        if args.output:
            Path(args.output).write_text(output)
        else:
            print(output)
        return

    # Generate report
    if args.format == "markdown":
        output = analyzer.to_markdown_report(args.top_n)
    elif args.format == "json":
        output = json.dumps({
            "rankings": analyzer.get_rankings().head(args.top_n).to_dict(orient="records"),
            "feature_frequency": analyzer.analyze_feature_frequency(args.top_n),
            "class_summary": analyzer.get_per_class_summary().to_dict(orient="records"),
            "recommendations": analyzer.generate_recommendations(args.top_n),
        }, indent=2, default=str)
    else:  # table
        output = analyzer.get_rankings().head(args.top_n).to_string()

    if args.output:
        Path(args.output).write_text(output)
        print(f"Report written to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
