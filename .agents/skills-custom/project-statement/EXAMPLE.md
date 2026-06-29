# EXAMPLE

A worked example showing a filled `PROJECT_STATEMENT.yaml` and the markdown it renders to.

## Filled YAML

```yaml
name: DIG013 Face Recognition
project_type: data-science

goal: |
  Deliver a face-recognition library running on Android (QNN), iOS (CoreML),
  with XNN fallback, meeting customer accuracy targets on their test set.

definition_of_done:
  - Demo apps run face detection + recognition end-to-end on Samsung Galaxy S24
  - Accuracy targets met on customer test set
  - Performance targets met (latency, model size)
  - Documentation handed over to customer

team:
  - name: Anna Kowalska
    role: Annotator
    joined: 2024-03
    left: 2024-09
  - name: Magda Jaśkiewicz
    role: Data Scientist (Tech Lead)
    joined: 2024-04
  - name: Piotr Nowak
    role: Software Developer
    joined: 2024-06

constraints:
  performance:
    - "target latency: <30ms on Snapdragon 8 Gen 3 NPU"
    - "model size: <50MB"
  accuracy:
    - "face detection mAP: >0.70 on customer test set"
  hardware:
    - "target device: Samsung Galaxy S24 (SM-S928B, Snapdragon 8 Gen 3)"
  deadlines:
    - "v1.0 release: 2026-08-15"

repositories:
  - name: dig013
    url: https://github.com/digica/dig013
    primary: true
    description: main project repo — pipelines, evaluation, exports
  - name: face-recognition-lib
    url: https://github.com/digica/face-recognition-lib
    description: C++ inference library, vendored as submodule under face-recognition-lib/
  - name: executorch
    url: https://github.com/digica/executorch
    description: fork of pytorch/executorch with QNN backend patches

tools:
  - name: Slack
    note: project channel
  - name: Jira
    url: https://digica.atlassian.net/jira/projects/MET004
    note: project board
  - name: Confluence
    url: https://digica.atlassian.net/wiki/spaces/DIG013
  - name: MLFlow
    url: https://mlflow.internal/experiments/dig013
  - name: DVC
    url: https://github.com/digica/dig013
    note: tracked under data/
  - name: CVAT
    url: https://cvat.internal/projects/dig013

folders:
  - location: gdrive
    purpose: customer reports
    url: https://drive.google.com/drive/folders/xyz123
  - location: gdrive
    purpose: shared with customer (read-only)
    url: https://drive.google.com/drive/folders/abc456
  - location: nas
    purpose: raw datasets root
    url: smb://nas.internal/dig013/datasets
  - location: nas
    purpose: model exports
    url: smb://nas.internal/dig013/exports

datasets:
  - name: dig013-faces-v3
    purpose: training set for SCRFD face detector
    location: nas
    url: smb://nas.internal/dig013/datasets/faces-v3
    license: proprietary (customer NDA)
    on_DVC: tracked
    version: 2024-07
    notes: customer-provided; ~12k images
  - name: lfw-benchmark
    purpose: external accuracy benchmark
    location: nas
    url: smb://nas.internal/dig013/datasets/lfw
    license: "CC BY 4.0"
    on_DVC: untracked
    notes: standard LFW dataset

experiment_log: https://docs.google.com/spreadsheets/d/1abc...xyz/edit
```

## Rendered markdown (paste into the company-template Google Doc)

```markdown
# 🚀 DIG013 Face Recognition
*Type: data-science · generated 2026-05-25*

## 🎯 Goal

Deliver a face-recognition library running on Android (QNN), iOS (CoreML),
with XNN fallback, meeting customer accuracy targets on their test set.

## ✅ Definition of Done

- Demo apps run face detection + recognition end-to-end on Samsung Galaxy S24
- Accuracy targets met on customer test set
- Performance targets met (latency, model size)
- Documentation handed over to customer

## 👥 Team

### Current
- Magda Jaśkiewicz — Data Scientist (Tech Lead) — since 2024-04
- Piotr Nowak — Software Developer — since 2024-06

### Past
- Anna Kowalska — Annotator — 2024-03 → 2024-09

## ⚙️ Constraints

### ⚡ Performance
- target latency: <30ms on Snapdragon 8 Gen 3 NPU
- model size: <50MB

### 🎯 Accuracy
- face detection mAP: >0.70 on customer test set

### 📱 Hardware
- target device: Samsung Galaxy S24 (SM-S928B, Snapdragon 8 Gen 3)

### 📅 Deadlines
- v1.0 release: 2026-08-15

## 🐙 Repositories

- ⭐ **dig013** — main project repo — pipelines, evaluation, exports
    - https://github.com/digica/dig013
- **face-recognition-lib** — C++ inference library, vendored as submodule under face-recognition-lib/
    - https://github.com/digica/face-recognition-lib
- **executorch** — fork of pytorch/executorch with QNN backend patches
    - https://github.com/digica/executorch

## 🔧 Tools

- 💬 **Slack** — project channel
- 🗂️ **Jira** — https://digica.atlassian.net/jira/projects/MET004 — project board
- 📘 **Confluence** — https://digica.atlassian.net/wiki/spaces/DIG013
- 📊 **MLFlow** — https://mlflow.internal/experiments/dig013
- 🧬 **DVC** — https://github.com/digica/dig013 — tracked under data/
- 🏷️ **CVAT** — https://cvat.internal/projects/dig013

## 📁 Folders

### 📁 GDrive
- customer reports — https://drive.google.com/drive/folders/xyz123
- shared with customer (read-only) — https://drive.google.com/drive/folders/abc456

### 💽 NAS
- raw datasets root — smb://nas.internal/dig013/datasets
- model exports — smb://nas.internal/dig013/exports

## 🗃️ Datasets

- **dig013-faces-v3** — training set for SCRFD face detector
    - 💽 NAS — smb://nas.internal/dig013/datasets/faces-v3
    - license: proprietary (customer NDA); on_DVC: tracked
    - version: 2024-07; customer-provided; ~12k images
- **lfw-benchmark** — external accuracy benchmark
    - 💽 NAS — smb://nas.internal/dig013/datasets/lfw
    - license: CC BY 4.0; on_DVC: untracked
    - standard LFW dataset

## 📊 Experiment Log

https://docs.google.com/spreadsheets/d/1abc...xyz/edit

---
*Maintained as `PROJECT_STATEMENT.yaml` in dig013. To update: edit the YAML and re-run `/project-statement`.*
```

## TODO example

A field marked as not-yet-decided uses the `TODO:` sentinel string:

```yaml
folders:
  - location: gdrive
    purpose: customer reports
    url: "TODO: create the folder once contract signs"
```

renders to:

```markdown
- customer reports — 🚧 TODO: create the folder once contract signs
```

The bottom line of `render.py`'s stderr summary shows the total TODO count so the user can see at a glance how much is unresolved.

## Software-project example (DS-only sections absent)

A `project_type: software` YAML simply omits `datasets:` and `experiment_log:`. The renderer skips both sections silently. All other sections work identically.
