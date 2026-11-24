"""APPGEN graph runtime engine (S007 lot 1).

This module provides a first backend runtime for appgen-graph with:
- node navigation
- condition-aware routing
- progression state handling
- resume from serialized state
"""

from __future__ import annotations

from dataclasses import dataclass, field
import copy
import re
from typing import Any, Mapping, MutableMapping


SUPPORTED_NODE_TYPES = {"question", "action", "router", "end", "group", "collection"}

# Formats de question à une seule étape suivante (`next` chaîne). Les autres
# (`choice`) portent une destination par choix (`next` dictionnaire).
SINGLE_NEXT_INPUT_TYPES = {"text", "multi", "number"}


class GraphValidationError(ValueError):
    """Raised when a graph definition is invalid."""


class GraphRuntimeError(RuntimeError):
    """Raised when runtime execution cannot continue."""


@dataclass
class GraphState:
    """Runtime progression state for one graph execution."""

    graph_id: str
    current_node_id: str
    answers: dict[str, Any] = field(default_factory=dict)
    history: list[str] = field(default_factory=list)
    is_finished: bool = False
    last_transition_reason: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "graph_id": self.graph_id,
            "current_node_id": self.current_node_id,
            "answers": copy.deepcopy(self.answers),
            "history": list(self.history),
            "is_finished": self.is_finished,
            "last_transition_reason": self.last_transition_reason,
        }

    @classmethod
    def from_dict(cls, payload: Mapping[str, Any]) -> "GraphState":
        return cls(
            graph_id=str(payload.get("graph_id", "")),
            current_node_id=str(payload.get("current_node_id", "")),
            answers=dict(payload.get("answers", {}) or {}),
            history=list(payload.get("history", []) or []),
            is_finished=bool(payload.get("is_finished", False)),
            last_transition_reason=payload.get("last_transition_reason"),
        )


class GraphEngine:
    """Executes appgen-graph JSON-like definitions."""

    def __init__(self, graph_definition: Mapping[str, Any]) -> None:
        self.graph_definition = copy.deepcopy(dict(graph_definition))
        self.graph_id = str(self.graph_definition.get("id") or "").strip()
        self.start_node_id = str(self.graph_definition.get("start_node") or "").strip()
        self.fallback_node_id = (
            str(self.graph_definition.get("fallback_node") or "").strip() or None
        )
        self.nodes = self._normalize_nodes(self.graph_definition.get("nodes"))
        self._validate_graph()

    def start(self, state: GraphState | Mapping[str, Any] | None = None) -> GraphState:
        """Create or restore state, then auto-resolve routers/skipped nodes."""
        if state is None:
            runtime_state = GraphState(
                graph_id=self.graph_id,
                current_node_id=self.start_node_id,
            )
        else:
            runtime_state = self.load_state(state)
        return self._advance_auto(runtime_state)

    def load_state(self, state: GraphState | Mapping[str, Any]) -> GraphState:
        """Load a serialized state and normalize it for this graph."""
        runtime_state = (
            copy.deepcopy(state)
            if isinstance(state, GraphState)
            else GraphState.from_dict(state)
        )
        if runtime_state.graph_id and runtime_state.graph_id != self.graph_id:
            raise GraphRuntimeError(
                f"State belongs to graph '{runtime_state.graph_id}', expected '{self.graph_id}'."
            )
        runtime_state.graph_id = self.graph_id

        if runtime_state.current_node_id not in self.nodes:
            runtime_state.current_node_id = self.start_node_id
            runtime_state.history = []
            runtime_state.last_transition_reason = "state_reset_invalid_node"
            runtime_state.is_finished = False

        return self._advance_auto(runtime_state)

    def snapshot(self, state: GraphState) -> dict[str, Any]:
        """Serialize state for persistence."""
        return state.to_dict()

    def current_node(self, state: GraphState) -> dict[str, Any]:
        """Return a safe copy of the current node."""
        return copy.deepcopy(self.nodes[state.current_node_id])

    def answer(self, state: GraphState, value: Any | None = None) -> GraphState:
        """Advance one interactive step from current node."""
        node = self.nodes[state.current_node_id]
        node_type = node["type"]

        if node_type == "end":
            state.is_finished = True
            state.last_transition_reason = "already_end"
            return state

        if node_type == "router":
            next_id = self._resolve_router(node, state.answers)
            reason = "router"
        elif node_type == "action":
            next_id = self._require_string(node.get("next"), f"{node['id']}.next")
            reason = "action_complete"
        elif node_type == "question":
            if str(node.get("input_type", "choice")) == "number":
                value = self.parse_number_answer(node, value)
            next_id = self._resolve_question_next(node, value)
            input_key = self._require_string(node.get("input_key"), f"{node['id']}.input_key")
            state.answers[input_key] = value
            reason = "question_answered"
        elif node_type == "group":
            next_id = self._resolve_group_next(node, state.answers, value)
            reason = "group_resolved"
        elif node_type == "collection":
            next_id = self._require_string(node.get("next"), f"{node['id']}.next")
            output_key = self._require_string(node.get("output_key"), f"{node['id']}.output_key")
            state.answers[output_key] = self._validate_collection_value(node, value)
            reason = "collection_submitted"
        else:
            raise GraphRuntimeError(f"Unsupported node type at runtime: {node_type}")

        self._transition(state, next_id, reason)
        return self._advance_auto(state)

    def _advance_auto(self, state: GraphState) -> GraphState:
        """Auto-traverse router nodes and nodes hidden by `when` rules."""
        hops = 0
        max_hops = max(1, len(self.nodes) * 4)

        while hops < max_hops:
            node = self.nodes[state.current_node_id]
            node_type = node["type"]

            if node_type == "end":
                state.is_finished = True
                if not state.last_transition_reason:
                    state.last_transition_reason = "reached_end"
                return state

            if self._should_skip_node(node, state.answers):
                skip_next = self._resolve_skip_target(node)
                self._transition(state, skip_next, "node_skipped")
                hops += 1
                continue

            if node_type == "router":
                router_next = self._resolve_router(node, state.answers)
                self._transition(state, router_next, "router")
                hops += 1
                continue

            state.is_finished = False
            return state

        raise GraphRuntimeError("Auto-advance exceeded maximum hops; check for graph loops.")

    def _transition(self, state: GraphState, next_node_id: str, reason: str) -> None:
        if next_node_id not in self.nodes:
            raise GraphRuntimeError(f"Next node '{next_node_id}' is missing.")
        state.history.append(state.current_node_id)
        state.current_node_id = next_node_id
        state.last_transition_reason = reason
        state.is_finished = False

    def _normalize_nodes(self, raw_nodes: Any) -> dict[str, dict[str, Any]]:
        if isinstance(raw_nodes, Mapping):
            nodes: dict[str, dict[str, Any]] = {}
            for node_id, node in raw_nodes.items():
                if not isinstance(node, MutableMapping):
                    raise GraphValidationError(f"Node '{node_id}' must be an object.")
                normalized = copy.deepcopy(dict(node))
                normalized.setdefault("id", str(node_id))
                nodes[str(node_id)] = normalized
            return nodes

        if isinstance(raw_nodes, list):
            nodes = {}
            for index, node in enumerate(raw_nodes):
                if not isinstance(node, MutableMapping):
                    raise GraphValidationError(f"Node at index {index} must be an object.")
                normalized = copy.deepcopy(dict(node))
                node_id = str(normalized.get("id") or "").strip()
                if not node_id:
                    raise GraphValidationError(f"Node at index {index} has no id.")
                if node_id in nodes:
                    raise GraphValidationError(f"Duplicate node id '{node_id}'.")
                nodes[node_id] = normalized
            return nodes

        raise GraphValidationError("Graph field 'nodes' must be an array or object map.")

    def _validate_graph(self) -> None:
        if not self.graph_id:
            raise GraphValidationError("Graph field 'id' is required.")
        if not self.start_node_id:
            raise GraphValidationError("Graph field 'start_node' is required.")
        if self.start_node_id not in self.nodes:
            raise GraphValidationError(
                f"Graph start_node '{self.start_node_id}' does not exist in nodes."
            )
        if self.fallback_node_id and self.fallback_node_id not in self.nodes:
            raise GraphValidationError(
                f"Graph fallback_node '{self.fallback_node_id}' does not exist in nodes."
            )

        for node_id, node in self.nodes.items():
            node_type = self._require_string(node.get("type"), f"{node_id}.type").lower()
            if node_type not in SUPPORTED_NODE_TYPES:
                raise GraphValidationError(
                    f"Node '{node_id}' has unsupported type '{node_type}'."
                )
            node["type"] = node_type

            if node_type == "collection":
                self._validate_collection_schema(node)

            refs = self._collect_next_references(node)
            for ref in refs:
                if ref not in self.nodes:
                    raise GraphValidationError(
                        f"Node '{node_id}' points to missing node '{ref}'."
                    )

    def _collect_next_references(self, node: Mapping[str, Any]) -> list[str]:
        node_type = node["type"]
        refs: list[str] = []

        default_next = node.get("default_next")
        if default_next is not None:
            refs.append(self._require_string(default_next, f"{node['id']}.default_next"))

        if node_type == "action":
            refs.append(self._require_string(node.get("next"), f"{node['id']}.next"))
            return refs

        if node_type == "question":
            self._require_string(node.get("input_key"), f"{node['id']}.input_key")
            input_type = str(node.get("input_type", "choice"))
            next_field = node.get("next")
            if input_type == "number":
                self._validate_number_bounds(node)
            if input_type in SINGLE_NEXT_INPUT_TYPES:
                refs.append(self._require_string(next_field, f"{node['id']}.next"))
            else:
                if not isinstance(next_field, Mapping) or not next_field:
                    raise GraphValidationError(
                        f"Question '{node['id']}' requires a non-empty next map."
                    )
                for answer_value, target in next_field.items():
                    refs.append(
                        self._require_string(
                            target,
                            f"{node['id']}.next[{answer_value}]",
                        )
                    )
            return refs

        if node_type == "router":
            routes = node.get("routes")
            if not isinstance(routes, list) or not routes:
                raise GraphValidationError(f"Router '{node['id']}' requires non-empty routes.")
            for index, route in enumerate(routes):
                if not isinstance(route, Mapping):
                    raise GraphValidationError(
                        f"Router '{node['id']}' route[{index}] must be an object."
                    )
                refs.append(
                    self._require_string(route.get("next"), f"{node['id']}.routes[{index}].next")
                )
            if "default_next" not in node:
                raise GraphValidationError(f"Router '{node['id']}' requires default_next.")
            return refs

        if node_type == "group":
            refs.append(self._require_string(node.get("next"), f"{node['id']}.next"))
            return refs

        if node_type == "collection":
            refs.append(self._require_string(node.get("next"), f"{node['id']}.next"))
            return refs

        return refs

    def _validate_collection_schema(self, node: Mapping[str, Any]) -> None:
        """Validate a `collection` node's shape at graph-load time.

        A collection captures a variable-length list of structured items in a
        single answer (like `multi`, but each item has several sub-fields)
        instead of a graph-native loop: the engine stays a simple DAG walker,
        the repeat UX ("ajouter un autre ?") lives entirely client-side.
        """
        node_id = node["id"]
        self._require_string(node.get("output_key"), f"{node_id}.output_key")
        schema = node.get("item_schema")
        if not isinstance(schema, list) or not schema:
            raise GraphValidationError(
                f"Collection '{node_id}' requires a non-empty item_schema."
            )
        seen_keys: set[str] = set()
        for index, field in enumerate(schema):
            if not isinstance(field, Mapping):
                raise GraphValidationError(
                    f"Collection '{node_id}' item_schema[{index}] must be an object."
                )
            key = self._require_string(
                field.get("key"), f"{node_id}.item_schema[{index}].key"
            )
            if key in seen_keys:
                raise GraphValidationError(
                    f"Collection '{node_id}' item_schema has duplicate key '{key}'."
                )
            seen_keys.add(key)

        min_items = node.get("min_items", 0)
        if not isinstance(min_items, int) or isinstance(min_items, bool) or min_items < 0:
            raise GraphValidationError(
                f"Collection '{node_id}' min_items must be a non-negative int."
            )
        max_items = node.get("max_items")
        if max_items is not None:
            if (
                not isinstance(max_items, int)
                or isinstance(max_items, bool)
                or max_items < min_items
            ):
                raise GraphValidationError(
                    f"Collection '{node_id}' max_items must be an int >= min_items."
                )

    def _validate_collection_value(self, node: Mapping[str, Any], value: Any) -> list[dict[str, Any]]:
        node_id = node["id"]
        if value is None:
            items: list[Any] = []
        elif isinstance(value, list):
            items = value
        else:
            raise GraphRuntimeError(f"Collection '{node_id}' expects a list value.")

        schema = node.get("item_schema") or []
        known_keys = [
            str(field["key"]) for field in schema if isinstance(field, Mapping)
        ]
        required_keys = [
            str(field["key"])
            for field in schema
            if isinstance(field, Mapping) and field.get("required")
        ]

        min_items = int(node.get("min_items", 0) or 0)
        max_items = node.get("max_items")

        if len(items) < min_items:
            raise GraphRuntimeError(
                f"Collection '{node_id}' requires at least {min_items} item(s), "
                f"got {len(items)}."
            )
        if max_items is not None and len(items) > int(max_items):
            raise GraphRuntimeError(
                f"Collection '{node_id}' accepts at most {max_items} item(s), "
                f"got {len(items)}."
            )

        normalized_items: list[dict[str, Any]] = []
        for index, item in enumerate(items):
            if not isinstance(item, Mapping):
                raise GraphRuntimeError(
                    f"Collection '{node_id}' item[{index}] must be an object."
                )
            for key in required_keys:
                if not str(item.get(key, "")).strip():
                    raise GraphRuntimeError(
                        f"Collection '{node_id}' item[{index}] missing required field '{key}'."
                    )
            normalized_items.append({key: item.get(key, "") for key in known_keys})
        return normalized_items

    def _resolve_question_next(self, node: Mapping[str, Any], value: Any) -> str:
        input_type = str(node.get("input_type", "choice"))
        next_field = node.get("next")
        if input_type in SINGLE_NEXT_INPUT_TYPES:
            return self._require_string(next_field, f"{node['id']}.next")

        if not isinstance(next_field, Mapping):
            raise GraphRuntimeError(f"Question '{node['id']}' next map is invalid.")
        if value in next_field:
            return self._require_string(next_field[value], f"{node['id']}.next[{value}]")

        key = str(value)
        if key in next_field:
            return self._require_string(next_field[key], f"{node['id']}.next[{key}]")

        fallback = node.get("default_next") or self.fallback_node_id
        if fallback:
            return self._require_string(fallback, f"{node['id']}.default_next")

        raise GraphRuntimeError(
            f"Question '{node['id']}' has no next transition for answer '{value}'."
        )

    def _resolve_router(self, node: Mapping[str, Any], answers: Mapping[str, Any]) -> str:
        routes = node.get("routes") or []
        for route in routes:
            if not isinstance(route, Mapping):
                continue
            condition = route.get("when")
            if self.evaluate_condition(condition, answers):
                return self._require_string(route.get("next"), f"{node['id']}.route.next")
        return self._require_string(node.get("default_next"), f"{node['id']}.default_next")

    def _resolve_group_next(
        self,
        node: Mapping[str, Any],
        answers: Mapping[str, Any],
        value: Any,
    ) -> str:
        # Lot 1: group node delegates to plain `next`. Advanced loops are out of scope.
        _ = answers
        _ = value
        return self._require_string(node.get("next"), f"{node['id']}.next")

    def _should_skip_node(self, node: Mapping[str, Any], answers: Mapping[str, Any]) -> bool:
        if "when" not in node:
            return False
        return not self.evaluate_condition(node.get("when"), answers)

    def _resolve_skip_target(self, node: Mapping[str, Any]) -> str:
        if node.get("default_next"):
            return self._require_string(node.get("default_next"), f"{node['id']}.default_next")
        if node.get("next"):
            return self._require_string(node.get("next"), f"{node['id']}.next")
        if self.fallback_node_id:
            return self.fallback_node_id
        raise GraphRuntimeError(
            f"Node '{node['id']}' skipped by condition but no default_next/fallback available."
        )

    def evaluate_condition(
        self,
        condition: Any,
        answers: Mapping[str, Any],
    ) -> bool:
        if condition is None:
            return True
        if isinstance(condition, bool):
            return condition
        if isinstance(condition, (int, float)):
            return bool(condition)
        if isinstance(condition, str):
            return bool(condition.strip())
        if isinstance(condition, list):
            return all(self.evaluate_condition(item, answers) for item in condition)
        if not isinstance(condition, Mapping):
            raise GraphRuntimeError(f"Unsupported condition type: {type(condition)!r}")

        if "and" in condition:
            values = condition["and"]
            if not isinstance(values, list):
                raise GraphRuntimeError("Condition 'and' must be a list.")
            return all(self.evaluate_condition(item, answers) for item in values)

        if "or" in condition:
            values = condition["or"]
            if not isinstance(values, list):
                raise GraphRuntimeError("Condition 'or' must be a list.")
            return any(self.evaluate_condition(item, answers) for item in values)

        if "not" in condition:
            return not self.evaluate_condition(condition["not"], answers)

        if "missing" in condition:
            keys = condition["missing"]
            if not isinstance(keys, list):
                raise GraphRuntimeError("Condition 'missing' must be a list.")
            missing_keys = [key for key in keys if self._get_path(answers, str(key)) is None]
            return bool(missing_keys)

        if "exists" in condition:
            return self._get_path(answers, str(condition["exists"])) is not None

        if "==" in condition:
            left, right = self._binary_operands(condition["=="])
            return self._resolve_operand(left, answers) == self._resolve_operand(right, answers)

        if "!=" in condition:
            left, right = self._binary_operands(condition["!="])
            return self._resolve_operand(left, answers) != self._resolve_operand(right, answers)

        if ">" in condition:
            left, right = self._binary_operands(condition[">"])
            return self._to_number(self._resolve_operand(left, answers)) > self._to_number(
                self._resolve_operand(right, answers)
            )

        if ">=" in condition:
            left, right = self._binary_operands(condition[">="])
            return self._to_number(self._resolve_operand(left, answers)) >= self._to_number(
                self._resolve_operand(right, answers)
            )

        if "<" in condition:
            left, right = self._binary_operands(condition["<"])
            return self._to_number(self._resolve_operand(left, answers)) < self._to_number(
                self._resolve_operand(right, answers)
            )

        if "<=" in condition:
            left, right = self._binary_operands(condition["<="])
            return self._to_number(self._resolve_operand(left, answers)) <= self._to_number(
                self._resolve_operand(right, answers)
            )

        if "in" in condition:
            left, right = self._binary_operands(condition["in"])
            value = self._resolve_operand(left, answers)
            collection = self._resolve_operand(right, answers)
            try:
                return value in collection
            except TypeError:
                return False

        if "contains" in condition:
            left, right = self._binary_operands(condition["contains"])
            collection = self._resolve_operand(left, answers)
            value = self._resolve_operand(right, answers)
            try:
                return value in collection
            except TypeError:
                return False

        if "var" in condition:
            value = self._resolve_operand(condition, answers)
            return bool(value)

        raise GraphRuntimeError(f"Unsupported condition operator: {list(condition.keys())}")

    def _resolve_operand(self, operand: Any, answers: Mapping[str, Any]) -> Any:
        if isinstance(operand, Mapping) and "var" in operand:
            var_expr = operand["var"]
            default_value = None
            if isinstance(var_expr, list):
                path = str(var_expr[0]) if var_expr else ""
                default_value = var_expr[1] if len(var_expr) > 1 else None
            else:
                path = str(var_expr)
            value = self._get_path(answers, path)
            return default_value if value is None else value
        return operand

    @staticmethod
    def _binary_operands(value: Any) -> tuple[Any, Any]:
        if not isinstance(value, list) or len(value) != 2:
            raise GraphRuntimeError("Binary operator requires a list of two operands.")
        return value[0], value[1]

    @staticmethod
    def _get_path(data: Mapping[str, Any], dotted_path: str) -> Any:
        if not dotted_path:
            return None
        current: Any = data
        for part in dotted_path.split("."):
            if isinstance(current, Mapping) and part in current:
                current = current[part]
            else:
                return None
        return current

    @staticmethod
    def _bound(node: Mapping[str, Any], key: str) -> float | None:
        raw = node.get(key)
        if raw is None:
            return None
        if isinstance(raw, bool) or not isinstance(raw, (int, float)):
            raise GraphValidationError(f"Question '{node['id']}' {key} must be a number.")
        return float(raw)

    def _validate_number_bounds(self, node: Mapping[str, Any]) -> None:
        """`min`/`max` optionnels d'une question `number`, nombres et ordonnés."""
        low, high = self._bound(node, "min"), self._bound(node, "max")
        if low is not None and high is not None and low > high:
            raise GraphValidationError(f"Question '{node['id']}' min is greater than max.")

    def parse_number_answer(self, node: Mapping[str, Any], value: Any) -> int | float:
        """Réponse d'une question `number`, normalisée (même règle côté Dart).

        Accepte un nombre ou un texte (« 12,5 », « 1 200 »). Un entier reste
        un `int`, pour que `== 18` compare juste. Refuse ce qui n'est pas un
        nombre fini ou sort de `min`/`max`: une réponse invalide ne doit
        jamais atteindre une condition (le moteur lèverait plus loin).
        """
        if isinstance(value, bool):
            number = None
        elif isinstance(value, (int, float)):
            number = float(value)
        else:
            text = re.sub(r"[\s  ]", "", str(value if value is not None else ""))
            try:
                # `float` accepte « 1_000 », pas Dart: on le refuse des deux côtés.
                number = None if "_" in text else float(text.replace(",", "."))
            except ValueError:
                number = None
        if number is None or number != number or number in (float("inf"), float("-inf")):
            raise GraphRuntimeError(f"Question '{node['id']}' expects a number, got '{value}'.")
        low, high = self._bound(node, "min"), self._bound(node, "max")
        if (low is not None and number < low) or (high is not None and number > high):
            raise GraphRuntimeError(
                f"Question '{node['id']}' answer {number:g} is out of bounds [{low}, {high}]."
            )
        return int(number) if number.is_integer() else number

    @staticmethod
    def _to_number(value: Any) -> float:
        if isinstance(value, bool):
            return 1.0 if value else 0.0
        if isinstance(value, (int, float)):
            return float(value)
        try:
            return float(str(value))
        except (TypeError, ValueError) as exc:
            raise GraphRuntimeError(f"Cannot compare non-numeric value '{value}'.") from exc

    @staticmethod
    def _require_string(value: Any, field_name: str) -> str:
        if isinstance(value, str) and value.strip():
            return value.strip()
        raise GraphValidationError(f"Field '{field_name}' must be a non-empty string.")

