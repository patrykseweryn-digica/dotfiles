#!/usr/bin/env python3
"""Fetch MLflow experiment results with filtering and artifact download support."""

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import mlflow
import pandas as pd
from mlflow import MlflowClient
from mlflow.entities import Run


@dataclass
class MLFlowFetcher:
    """Fetch and filter MLflow experiment results."""

    host: str = "http://127.0.0.1"
    port: str = "8081"
    experiment_name: str = ""
    max_results: int = 1000

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
        self.tracking_uri = f"{self.host}:{self.port}"
        mlflow.set_tracking_uri(self.tracking_uri)
        self.client = MlflowClient(tracking_uri=self.tracking_uri)
        self.experiment = mlflow.get_experiment_by_name(self.experiment_name)

    def fetch_runs(
        self,
        filter_string: str | None = None,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
        status: str | None = None,
        exclude_nested: bool = True,
    ) -> list[Run]:
        """Fetch runs with optional filters."""
        if self.experiment is None:
            raise ValueError(f"Experiment '{self.experiment_name}' not found.")

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

    def extract_run_data(self, run: Run) -> dict:
        """Extract relevant data from a single run."""
        data = run.to_dictionary()
        params = data["data"]["params"]
        metrics = data["data"]["metrics"]
        tags = data["data"]["tags"]

        # Extract features
        features_used = params.get("config.data.features_to_use", "")

        # Extract F1 scores per class
        f1_scores = {}
        for class_name in self.classes_of_interest:
            key = f"{class_name}.f1_score.test"
            f1_scores[class_name] = metrics.get(key)

        # Extract other metrics
        other_metrics = {}
        for class_name in self.classes_of_interest:
            for metric in ["precision", "recall", "roc_auc", "balanced_accuracy"]:
                key = f"{class_name}.{metric}.test"
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
        self, run: Run, output_dir: Path
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

    def fetch_results_dataframe(self, runs: list[Run]) -> pd.DataFrame:
        """Create DataFrame with results from runs."""
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

        df = pd.DataFrame(rows)
        if not df.empty and "total.f1_score" in df.columns:
            df = df.sort_values("total.f1_score", ascending=False).reset_index(drop=True)
        return df

    def to_json(self, runs: list[Run], include_all_params: bool = False) -> str:
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
    parser.add_argument("experiment", help="MLflow experiment name")
    parser.add_argument("--host", default="http://127.0.0.1", help="MLflow host")
    parser.add_argument("--port", default="8081", help="MLflow port")
    parser.add_argument("--filter", dest="filter_string", help="MLflow filter string")
    parser.add_argument("--status", choices=["FINISHED", "RUNNING", "FAILED"], help="Filter by run status")
    parser.add_argument("--start-date", help="Filter runs after date (YYYY-MM-DD)")
    parser.add_argument("--end-date", help="Filter runs before date (YYYY-MM-DD)")
    parser.add_argument("--output", "-o", help="Output file path (JSON)")
    parser.add_argument("--format", choices=["json", "table"], default="json", help="Output format")
    parser.add_argument("--download-artifacts", action="store_true", help="Download feature importance artifacts")
    parser.add_argument("--artifacts-dir", default="./mlflow_artifacts", help="Directory for downloaded artifacts")
    return parser.parse_args()


def main():
    args = parse_args()

    # Parse dates
    start_time = datetime.strptime(args.start_date, "%Y-%m-%d") if args.start_date else None
    end_time = datetime.strptime(args.end_date, "%Y-%m-%d") if args.end_date else None

    # Fetch data
    fetcher = MLFlowFetcher(
        host=args.host,
        port=args.port,
        experiment_name=args.experiment,
    )

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
        df = fetcher.fetch_results_dataframe(runs)
        output = df.to_string()

    if args.output:
        Path(args.output).write_text(output)
        print(f"Results written to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
