#!/usr/bin/env python3
"""Fetch MLflow experiment results with filtering and artifact download support."""

import argparse
import importlib
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass
class MLFlowFetcher:
    """Fetch and filter MLflow experiment results."""

    tracking_uri: str = "http://127.0.0.1:8081"
    experiment_name: str | None = None
    experiment_id: str | None = None
    max_results: int = 1000
    feature_param: str = "config.data.features_to_use"
    f1_metric_template: str = "{class_name}.f1_score.test"
    other_metric_template: str = "{class_name}.{metric}.test"

    classes_of_interest: list[str] = field(
        default_factory=lambda: [
            "bird",
            "multi_rotor_drone",
            "fixed_wing_drone",
            "airplane",
            "total",
        ]
    )

    def __post_init__(self):
        try:
            self.mlflow = importlib.import_module("mlflow")
        except ImportError as exc:
            raise RuntimeError("mlflow is required for fetching runs. Install it in the active environment.") from exc

        self.mlflow.set_tracking_uri(self.tracking_uri)
        self.client = self.mlflow.MlflowClient(tracking_uri=self.tracking_uri)
        if self.experiment_id:
            self.experiment = self.client.get_experiment(self.experiment_id)
        elif self.experiment_name:
            self.experiment = self.mlflow.get_experiment_by_name(self.experiment_name)
        else:
            raise ValueError("Provide experiment_name or experiment_id.")

    def fetch_runs(
        self,
        filter_string: str | None = None,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
        status: str | None = None,
        exclude_nested: bool = True,
    ) -> list[Any]:
        """Fetch runs with optional filters."""
        if self.experiment is None:
            identifier = self.experiment_id or self.experiment_name
            raise ValueError(f"Experiment '{identifier}' not found.")

        # Build filter string
        filters = []
        if filter_string:
            filters.append(filter_string)
        if status:
            filters.append(f"attributes.status = '{status}'")

        combined_filter = " AND ".join(filters) if filters else ""

        search_kwargs = {
            "experiment_ids": [self.experiment.experiment_id],
            "max_results": self.max_results,
        }
        if combined_filter:
            search_kwargs["filter_string"] = combined_filter

        runs = self.client.search_runs(**search_kwargs)

        # Time-based filtering (post-query)
        if start_time:
            start_ts = int(start_time.timestamp() * 1000)
            runs = [r for r in runs if r.info.start_time >= start_ts]
        if end_time:
            end_ts = int(end_time.timestamp() * 1000)
            runs = [r for r in runs if r.info.start_time <= end_ts]

        # Exclude nested runs (fold runs)
        if exclude_nested:
            runs = [r for r in runs if r.info.run_name and not r.info.run_name.startswith("fold-")]

        return runs

    def extract_run_data(self, run: Any) -> dict:
        """Extract relevant data from a single run."""
        data = run.to_dictionary()
        params = data["data"]["params"]
        metrics = data["data"]["metrics"]
        tags = data["data"]["tags"]

        features_used = params.get(self.feature_param, "")

        # Extract F1 scores per class
        f1_scores = {}
        for class_name in self.classes_of_interest:
            key = self.f1_metric_template.format(class_name=class_name)
            f1_scores[class_name] = metrics.get(key)

        # Extract other metrics
        other_metrics = {}
        for class_name in self.classes_of_interest:
            for metric in ["precision", "recall", "roc_auc", "balanced_accuracy"]:
                key = self.other_metric_template.format(class_name=class_name, metric=metric)
                if key in metrics:
                    other_metrics[f"{class_name}.{metric}"] = metrics[key]

        return {
            "run_id": run.info.run_id,
            "run_name": run.info.run_name,
            "status": run.info.status,
            "start_time": run.info.start_time,
            "features_used": features_used,
            "f1_scores": f1_scores,
            "other_metrics": other_metrics,
            "params": {k: v for k, v in params.items() if k.startswith("config.")},
            "tags": tags,
        }

    def download_feature_importance(
        self, run: Any, output_dir: Path
    ) -> dict[str, str | None]:
        """Download feature importance artifacts for a run."""
        run_id = run.info.run_id
        artifacts = {}

        artifact_names = [
            "total.feature_importances.html",
            "total.permutation_importances.html",
            "total.shap_values.html",
        ]

        for artifact_name in artifact_names:
            try:
                local_path = self.client.download_artifacts(
                    run_id, artifact_name, dst_path=str(output_dir / run_id)
                )
                artifacts[artifact_name] = local_path
            except Exception:
                artifacts[artifact_name] = None

        return artifacts

    def fetch_results_rows(self, runs: list[Any]) -> list[dict]:
        """Create tabular result rows from runs."""
        rows = []
        for run in runs:
            data = self.extract_run_data(run)
            row = {
                "run_id": data["run_id"],
                "run_name": data["run_name"],
                "features_used": data["features_used"],
                "total.f1_score": data["f1_scores"].get("total"),
            }
            # Add per-class F1
            for class_name, score in data["f1_scores"].items():
                if class_name != "total":
                    row[f"{class_name}.f1_score"] = score
            rows.append(row)

        return sorted(rows, key=lambda row: row.get("total.f1_score") or 0, reverse=True)

    def fetch_results_table(self, runs: list[Any]) -> str:
        """Create a simple markdown table with results from runs."""
        rows = self.fetch_results_rows(runs)
        if not rows:
            return "_No data._"

        columns = list(rows[0].keys())
        lines = [
            "| " + " | ".join(columns) + " |",
            "| " + " | ".join("---" for _ in columns) + " |",
        ]
        for row in rows:
            lines.append("| " + " | ".join(str(row.get(column, "")) for column in columns) + " |")
        return "\n".join(lines)

    def to_json(self, runs: list[Any], include_all_params: bool = False) -> str:
        """Export runs data to JSON."""
        results = []
        for run in runs:
            data = self.extract_run_data(run)
            if not include_all_params:
                data.pop("params", None)
            results.append(data)

        # Sort by total F1
        results.sort(key=lambda x: x["f1_scores"].get("total") or 0, reverse=True)
        return json.dumps(results, indent=2, default=str)


def parse_args():
    parser = argparse.ArgumentParser(description="Fetch MLflow experiment results")
    parser.add_argument("experiment", nargs="?", help="MLflow experiment name")
    parser.add_argument("--experiment-id", help="MLflow experiment ID")
    parser.add_argument("--tracking-uri", help="MLflow tracking URI")
    parser.add_argument("--host", default="http://127.0.0.1", help="MLflow host, kept for backwards compatibility")
    parser.add_argument("--port", default="8081", help="MLflow port, kept for backwards compatibility")
    parser.add_argument("--filter", dest="filter_string", help="MLflow filter string")
    parser.add_argument("--status", choices=["FINISHED", "RUNNING", "FAILED"], help="Filter by run status")
    parser.add_argument("--start-date", help="Filter runs after date (YYYY-MM-DD)")
    parser.add_argument("--end-date", help="Filter runs before date (YYYY-MM-DD)")
    parser.add_argument("--classes", default="bird,multi_rotor_drone,fixed_wing_drone,airplane,total", help="Comma-separated class names")
    parser.add_argument("--feature-param", default="config.data.features_to_use", help="Run parameter containing feature set")
    parser.add_argument("--f1-metric-template", default="{class_name}.f1_score.test", help="Metric key template for F1 scores")
    parser.add_argument("--other-metric-template", default="{class_name}.{metric}.test", help="Metric key template for precision/recall/etc.")
    parser.add_argument("--output", "-o", help="Output file path (JSON)")
    parser.add_argument("--format", choices=["json", "table"], default="json", help="Output format")
    parser.add_argument("--download-artifacts", action="store_true", help="Download feature importance artifacts")
    parser.add_argument("--artifacts-dir", default="./mlflow_artifacts", help="Directory for downloaded artifacts")
    return parser.parse_args()


def main():
    args = parse_args()

    if not args.experiment and not args.experiment_id:
        print("Error: provide an experiment name or --experiment-id", file=sys.stderr)
        sys.exit(2)

    # Parse dates
    start_time = datetime.strptime(args.start_date, "%Y-%m-%d") if args.start_date else None
    end_time = datetime.strptime(args.end_date, "%Y-%m-%d") if args.end_date else None

    tracking_uri = args.tracking_uri or f"{args.host}:{args.port}"
    classes = [item.strip() for item in args.classes.split(",") if item.strip()]

    try:
        fetcher = MLFlowFetcher(
            tracking_uri=tracking_uri,
            experiment_name=args.experiment,
            experiment_id=args.experiment_id,
            classes_of_interest=classes,
            feature_param=args.feature_param,
            f1_metric_template=args.f1_metric_template,
            other_metric_template=args.other_metric_template,
        )
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    runs = fetcher.fetch_runs(
        filter_string=args.filter_string,
        start_time=start_time,
        end_time=end_time,
        status=args.status,
    )

    if not runs:
        print(f"No runs found for experiment '{args.experiment}'", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(runs)} runs", file=sys.stderr)

    # Download artifacts if requested
    if args.download_artifacts:
        artifacts_dir = Path(args.artifacts_dir)
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        for run in runs:
            fetcher.download_feature_importance(run, artifacts_dir)
        print(f"Artifacts downloaded to {artifacts_dir}", file=sys.stderr)

    # Output
    if args.format == "json":
        output = fetcher.to_json(runs)
    else:
        output = fetcher.fetch_results_table(runs)

    if args.output:
        Path(args.output).write_text(output)
        print(f"Results written to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
