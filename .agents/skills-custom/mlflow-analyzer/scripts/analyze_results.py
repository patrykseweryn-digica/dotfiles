#!/usr/bin/env python3
"""Analyze fetched MLflow experiment results."""

import argparse
import ast
import importlib
import json
import math
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


def mean(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def std(values: list[float]) -> float | None:
    if not values:
        return None
    avg = mean(values)
    if avg is None:
        return None
    return math.sqrt(sum((value - avg) ** 2 for value in values) / len(values))


def format_value(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.4f}"
    return "" if value is None else str(value).replace("|", r"\|")


def markdown_table(rows: list[dict], columns: list[str]) -> str:
    if not rows:
        return "_No data._"

    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join("---" for _ in columns) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(format_value(row.get(column)) for column in columns) + " |")
    return "\n".join(lines)


@dataclass
class ExperimentAnalyzer:
    """Analyze fetched MLflow experiment results."""

    data: list[dict]
    primary_metric: str = "total"
    feature_field: str = "features_used"
    metric_group_field: str = "f1_scores"
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

    def get_rankings(self) -> list[dict]:
        """Rank runs by primary metric score."""
        rows = []
        for item in self.data:
            metrics = item.get(self.metric_group_field, {})
            primary_score = metrics.get(self.primary_metric)
            if primary_score is None:
                continue

            row = {
                "run_name": item.get("run_name", ""),
                "features": item.get(self.feature_field, ""),
                f"{self.primary_metric}_score": primary_score,
            }
            for metric_name, value in metrics.items():
                if metric_name != self.primary_metric and value is not None:
                    row[f"{metric_name}_score"] = value
            rows.append(row)

        rows.sort(key=lambda row: row[f"{self.primary_metric}_score"], reverse=True)
        for rank, row in enumerate(rows, start=1):
            row["rank"] = rank
        return rows

    def get_top_runs(self, n: int | None = None) -> list[dict]:
        """Get top N runs by primary metric."""
        n = n or self.top_n
        return sorted(
            [
                item
                for item in self.data
                if item.get(self.metric_group_field, {}).get(self.primary_metric) is not None
            ],
            key=lambda item: item[self.metric_group_field][self.primary_metric],
            reverse=True,
        )[:n]

    def _parse_features(self, features_str: str) -> list[str]:
        """Parse feature string into feature names."""
        if not features_str:
            return []
        if features_str.startswith("[") and features_str.endswith("]"):
            try:
                value = ast.literal_eval(features_str)
                if isinstance(value, list):
                    return [str(item).strip() for item in value]
            except (ValueError, SyntaxError):
                pass
        if "|" in features_str:
            return [item.strip() for item in features_str.split("|") if item.strip()]
        if "," in features_str:
            return [item.strip() for item in features_str.split(",") if item.strip()]
        return [features_str.strip()]

    def analyze_feature_frequency(self, n: int | None = None) -> dict:
        """Analyze feature frequency in top N runs."""
        top_runs = self.get_top_runs(n)
        all_features: list[str] = []

        for run in top_runs:
            all_features.extend(self._parse_features(run.get(self.feature_field, "")))

        frequency = Counter(all_features)
        total_runs = len(top_runs)

        return {
            "feature_counts": dict(frequency.most_common()),
            "feature_percentages": {
                feature: count / total_runs * 100
                for feature, count in frequency.items()
            } if total_runs else {},
            "total_runs_analyzed": total_runs,
        }

    def compare_feature_sets(
        self, feature_set_a: str, feature_set_b: str, metric: str = "total"
    ) -> dict:
        """Statistical comparison between two feature sets."""
        runs_a = [item for item in self.data if item.get(self.feature_field) == feature_set_a]
        runs_b = [item for item in self.data if item.get(self.feature_field) == feature_set_b]

        if not runs_a or not runs_b:
            return {"error": "One or both feature sets not found"}

        scores_a = [
            run[self.metric_group_field][metric]
            for run in runs_a
            if run.get(self.metric_group_field, {}).get(metric) is not None
        ]
        scores_b = [
            run[self.metric_group_field][metric]
            for run in runs_b
            if run.get(self.metric_group_field, {}).get(metric) is not None
        ]

        result = {
            "feature_set_a": feature_set_a,
            "feature_set_b": feature_set_b,
            "metric": metric,
            "mean_a": mean(scores_a),
            "std_a": std(scores_a),
            "n_a": len(scores_a),
            "mean_b": mean(scores_b),
            "std_b": std(scores_b),
            "n_b": len(scores_b),
        }

        if len(scores_a) < 2 or len(scores_b) < 2:
            result["note"] = "Insufficient samples for statistical test"
            return result

        try:
            stats_module = importlib.import_module("scipy.stats")
        except ImportError:
            result["note"] = "scipy not installed; skipped Mann-Whitney U test"
            return result

        stat, p_value = stats_module.mannwhitneyu(scores_a, scores_b, alternative="two-sided")
        result.update({
            "mann_whitney_stat": stat,
            "p_value": p_value,
            "significant_at_005": p_value < 0.05,
        })
        return result

    def get_per_class_summary(self) -> list[dict]:
        """Summary statistics per class across all runs."""
        results = []
        for class_name in self.classes_of_interest:
            scores = [
                item[self.metric_group_field][class_name]
                for item in self.data
                if item.get(self.metric_group_field, {}).get(class_name) is not None
            ]
            if scores:
                results.append({
                    "class": class_name,
                    "mean_score": mean(scores),
                    "std_score": std(scores),
                    "min_score": min(scores),
                    "max_score": max(scores),
                    "n_runs": len(scores),
                })
        return results

    def generate_recommendations(self, top_n: int = 5) -> list[str]:
        """Generate actionable recommendations based on analysis."""
        top_runs = self.get_top_runs(top_n)
        if not top_runs:
            return ["No runs found with valid metrics."]

        recommendations = []
        best = top_runs[0]
        best_score = best[self.metric_group_field].get(self.primary_metric)
        recommendations.append(
            f"Best run achieves {self.primary_metric} score of {best_score:.4f} using features: {best.get(self.feature_field, '')}"
        )

        freq = self.analyze_feature_frequency(top_n)
        if freq["feature_counts"]:
            top_features = list(freq["feature_counts"].keys())[:3]
            recommendations.append(
                f"Most frequent features in top {top_n} runs: {', '.join(top_features)}"
            )

        class_summary = self.get_per_class_summary()
        non_total = [row for row in class_summary if row["class"] != "total"]
        if non_total:
            hardest = min(non_total, key=lambda row: row["mean_score"])
            recommendations.append(
                f"Hardest class: {hardest['class']} (mean score: {hardest['mean_score']:.4f})"
            )

        return recommendations

    def to_markdown_report(self, top_n: int = 10) -> str:
        """Generate full markdown analysis report."""
        ranking_rows = self.get_rankings()[:top_n]
        ranking_columns = list(ranking_rows[0].keys()) if ranking_rows else []

        lines = ["# MLflow Experiment Analysis Report\n"]

        lines.append("## Top Runs\n")
        lines.append(markdown_table(ranking_rows, ranking_columns))
        lines.append("")

        lines.append("## Feature Frequency in Top Runs\n")
        freq = self.analyze_feature_frequency(top_n)
        if freq["feature_counts"]:
            for feature, count in freq["feature_counts"].items():
                pct = freq["feature_percentages"][feature]
                lines.append(f"- **{feature}**: {count}/{freq['total_runs_analyzed']} runs ({pct:.0f}%)")
        else:
            lines.append("_No feature data._")
        lines.append("")

        lines.append("## Per-Class Performance Summary\n")
        class_summary = self.get_per_class_summary()
        lines.append(markdown_table(
            class_summary,
            ["class", "mean_score", "std_score", "min_score", "max_score", "n_runs"],
        ))
        lines.append("")

        lines.append("## Recommendations\n")
        for rec in self.generate_recommendations(top_n):
            lines.append(f"- {rec}")
        lines.append("")

        return "\n".join(lines)


def parse_args():
    parser = argparse.ArgumentParser(description="Analyze MLflow experiment results")
    parser.add_argument("input", help="JSON file with fetched results")
    parser.add_argument("--top-n", type=int, default=10, help="Number of top runs to analyze")
    parser.add_argument("--metric", default="total", help="Primary metric name/class")
    parser.add_argument("--feature-field", default="features_used", help="Field containing the feature-set label")
    parser.add_argument("--metric-group-field", default="f1_scores", help="Field containing metric scores by class/name")
    parser.add_argument("--output", "-o", help="Output file path")
    parser.add_argument("--format", choices=["markdown", "json", "table"], default="markdown")
    parser.add_argument("--compare", nargs=2, metavar=("SET_A", "SET_B"), help="Compare two feature sets")
    return parser.parse_args()


def load_results(path: Path) -> list[dict]:
    """Load fetched results while accepting a future metadata wrapper."""
    with open(path) as f:
        data = json.load(f)

    if isinstance(data, list):
        return data
    if isinstance(data, dict) and isinstance(data.get("runs"), list):
        return data["runs"]

    raise ValueError("Input JSON must be a list of runs or an object with a 'runs' list.")


def main():
    args = parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    try:
        data = load_results(input_path)
    except ValueError as exc:
        print(f"Invalid input: {exc}", file=sys.stderr)
        sys.exit(1)

    analyzer = ExperimentAnalyzer(
        data=data,
        primary_metric=args.metric,
        feature_field=args.feature_field,
        metric_group_field=args.metric_group_field,
        top_n=args.top_n,
    )

    if args.compare:
        output = json.dumps(
            analyzer.compare_feature_sets(args.compare[0], args.compare[1], args.metric),
            indent=2,
            default=str,
        )
    elif args.format == "markdown":
        output = analyzer.to_markdown_report(args.top_n)
    elif args.format == "json":
        output = json.dumps({
            "rankings": analyzer.get_rankings()[:args.top_n],
            "feature_frequency": analyzer.analyze_feature_frequency(args.top_n),
            "class_summary": analyzer.get_per_class_summary(),
            "recommendations": analyzer.generate_recommendations(args.top_n),
        }, indent=2, default=str)
    else:
        rows = analyzer.get_rankings()[:args.top_n]
        output = markdown_table(rows, list(rows[0].keys()) if rows else [])

    if args.output:
        Path(args.output).write_text(output)
        print(f"Report written to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
