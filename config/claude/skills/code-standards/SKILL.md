# Code Standards

## Python & Tooling

- Python 3.13+
- Package manager: `uv` only (no pip)
- Typecheck: `pyright` (basic mode)
- Lint/format: `ruff`

## Commands

```bash
uv sync              # Install deps
uv run ruff check    # Lint
uv run ruff format   # Format
uv run pyright       # Typecheck
pytest tests/        # Test
```

## Formatting

- Line length: 110
- Formatter: `ruff format`

## Linting (Ruff)

Rules enabled: E, F, I, T, UP, B

| Rule | Description |
|------|-------------|
| E | PEP 8 style |
| F | Pyflakes (errors, unused) |
| I | isort (import order) |
| T | No print() |
| UP | pyupgrade (modern syntax) |
| B | bugbear (common bugs) |

## Type Hints

Required on all public functions. Use Python 3.13+ syntax:

```python
# Good
def get_user(user_id: str) -> User | None: ...
def process(items: list[str]) -> dict[str, int]: ...

# Bad
def get_user(user_id: str) -> Optional[User]: ...
def process(items: List[str]) -> Dict[str, int]: ...
```

## Imports

Order: stdlib → 3rd-party → local (enforced by ruff I)

```python
import os
from pathlib import Path

from pydantic import BaseModel
from rich import print

from models.entity import Entity
from helpers.utils import normalize
```

Style: Absolute imports only (no relative `from .module`)

## Docstrings

Google style for public functions:

```python
def search_entity(name: str, limit: int = 10) -> list[Entity]:
    """Search entities by name.

    Args:
        name: Entity name to search.
        limit: Max results to return.

    Returns:
        List of matching entities.

    Raises:
        ValueError: If name is empty.
    """
```

## Naming

PEP 8 standard:
- Classes: `PascalCase`
- Functions/variables: `snake_case`
- Constants: `UPPER_SNAKE_CASE`
- Private: `_single_underscore`

## Console Output

No `print()` - use `rich`:

```python
# Good
from rich import print
from rich.console import Console

console = Console()
print("[green]Success[/green]")
console.print(table)

# Bad
print("Success")
```

## Pydantic Models

Use Pydantic for all data structures:

```python
from pydantic import BaseModel, Field, field_validator

class Entity(BaseModel):
    """Entity with validation."""

    id: str
    name: str = Field(min_length=1)
    score: float = Field(ge=0.0, le=1.0)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, v: str) -> str:
        return v.strip()
```

Patterns:
- `Field()` for constraints and metadata
- `field_validator` / `model_validator` for custom logic
- `model_config = {"frozen": True}` for immutability
- `computed_field` for derived properties

## Error Handling

- Use specific exception types
- Include context in error messages
- Log errors with rich console

```python
class EntityNotFoundError(Exception):
    """Raised when entity lookup fails."""
    pass

def get_entity(id: str) -> Entity:
    entity = db.find(id)
    if not entity:
        raise EntityNotFoundError(f"Entity not found: {id}")
    return entity
```

## Testing

Framework: `pytest`

```python
# tests/test_entity.py
import pytest
from models.entity import Entity

def test_entity_validation():
    entity = Entity(id="1", name="Test", score=0.5)
    assert entity.name == "Test"

def test_entity_invalid_score():
    with pytest.raises(ValidationError):
        Entity(id="1", name="Test", score=2.0)

@pytest.fixture
def sample_entity() -> Entity:
    return Entity(id="1", name="Sample", score=0.8)
```

Naming: `test_*.py` files, `test_*` functions

## Pre-commit Hooks

Required hooks (`.pre-commit-config.yaml`):

- `ruff` - lint
- `ruff-format` - format
- `pyright` - typecheck
- `bandit` - security
- `check-ast` - syntax validation
- `check-json`, `check-yaml`, `check-toml` - config validation
- `end-of-file-fixer` - trailing newline
- `trailing-whitespace` - remove trailing spaces
- `debug-statements` - catch breakpoints
