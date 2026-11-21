#!/usr/bin/env python3
"""Generate temporary SymPy TeX expressions for ad-hoc oracle stress testing.

Writes generated `.tex` files strictly into `build/sympy_corpus/` (which is
gitignored) and pipes them through `node tool/oracle/render.mjs` to validate
against the pinned MathJax oracle. Generated expressions are never written into
`corpus/` or committed to version control.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import random
import subprocess
import sys
from typing import Any


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            'Generate temporary SymPy TeX expressions under build/sympy_corpus/ '
            'and run them through tool/oracle/render.mjs.'
        )
    )
    parser.add_argument(
        '--output-dir',
        default='build/sympy_corpus',
        help='Temporary output directory (must remain outside corpus/).',
    )
    parser.add_argument(
        '--count',
        type=int,
        default=48,
        help='Number of symbolic expressions to generate.',
    )
    parser.add_argument(
        '--seed',
        type=int,
        default=42,
        help='Deterministic random seed for expression generation.',
    )
    parser.add_argument(
        '--skip-oracle',
        action='store_true',
        help='Write temporary .tex files without running tool/oracle/render.mjs.',
    )
    return parser.parse_args(argv)


def ensure_safe_output_dir(repo_root: pathlib.Path, raw_output: str) -> pathlib.Path:
    output_dir = (repo_root / raw_output).resolve()
    corpus_dir = (repo_root / 'corpus').resolve()
    if output_dir == corpus_dir or corpus_dir in output_dir.parents:
        raise ValueError(
            'Refusing to write SymPy output inside corpus/; '
            'use a gitignored directory such as build/sympy_corpus.'
        )
    return output_dir


def build_expressions(count: int, seed: int) -> list[dict[str, Any]]:
    import sympy as sp

    rng = random.Random(seed)
    x, y, z, t, n, k = sp.symbols('x y z t n k')
    alpha, beta, theta = sp.symbols('alpha beta theta')
    f = sp.Function('f')

    templates: list[tuple[str, Any]] = [
        ('polynomial_rational', lambda: (x**3 + rng.randint(1, 9) * x - 1) / (y**2 + 1)),
        ('trig_combo', lambda: sp.sin(alpha * x) ** 2 + sp.cos(beta * x + theta)),
        ('exp_log', lambda: sp.exp(-alpha * x**2) * sp.log(1 + y**2)),
        ('derivative', lambda: sp.Derivative(sp.sin(x * y) / (1 + x**2), x, 2)),
        ('definite_integral', lambda: sp.Integral(sp.exp(-t**2) * sp.cos(alpha * t), (t, 0, sp.oo))),
        ('indefinite_integral', lambda: sp.Integral(x**2 * sp.sqrt(1 - x**2), x)),
        ('summation', lambda: sp.Sum((-1) ** k * x ** (2 * k + 1) / sp.factorial(2 * k + 1), (k, 0, n))),
        ('product', lambda: sp.Product(1 + x / (k**2 + 1), (k, 1, n))),
        ('limit', lambda: sp.Limit((sp.sin(x) - x) / x**3, x, 0)),
        (
            'matrix_3x3',
            lambda: sp.Matrix([
                [1, alpha, x],
                [-alpha, sp.cos(theta), y],
                [0, z, sp.exp(t)],
            ]),
        ),
        (
            'piecewise',
            lambda: sp.Piecewise(
                (x**2, x < 0),
                (sp.sin(x), x <= sp.pi),
                (sp.log(x), True),
            ),
        ),
        (
            'ode_relation',
            lambda: sp.Eq(sp.Derivative(f(x), x, 2) + alpha * f(x), sp.sin(beta * x)),
        ),
    ]

    cases: list[dict[str, Any]] = []
    for index in range(count):
        feature, factory = templates[index % len(templates)]
        expr = factory()
        tex = sp.latex(expr)
        display = 'display' if index % 3 != 0 else 'inline'
        cases.append({
            'id': f'sympy_{index:04d}_{feature}',
            'feature': feature,
            'display': display,
            'tex': tex,
        })
    return cases


def write_corpus_files(output_dir: pathlib.Path, cases: list[dict[str, Any]]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for existing in output_dir.glob('*.tex'):
        existing.unlink()
    for case in cases:
        content = (
            f"% id: {case['id']}\n"
            f"% feature: {case['feature']}\n"
            f"% display: {case['display']}\n"
            f"{case['tex']}\n"
        )
        (output_dir / f"{case['id']}.tex").write_text(content, encoding='utf-8')


def run_oracle(repo_root: pathlib.Path, cases: list[dict[str, Any]]) -> dict[str, Any]:
    oracle_script = repo_root / 'tool' / 'oracle' / 'render.mjs'
    if not oracle_script.exists():
        raise FileNotFoundError(f'Missing oracle entrypoint: {oracle_script}')
    payload = [
        {
            'id': case['id'],
            'tex': case['tex'],
            'display': case['display'] == 'display',
        }
        for case in cases
    ]
    proc = subprocess.run(
        ['node', str(oracle_script)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        cwd=str(repo_root),
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f'Oracle exited with status {proc.returncode}: {proc.stderr.strip()}'
        )
    parsed: dict[str, Any] = json.loads(proc.stdout)
    return parsed


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.count <= 0:
        print('Error: --count must be positive.', file=sys.stderr)
        return 2

    repo_root = pathlib.Path(__file__).resolve().parent.parent
    try:
        output_dir = ensure_safe_output_dir(repo_root, args.output_dir)
    except ValueError as err:
        print(f'Error: {err}', file=sys.stderr)
        return 2

    try:
        import sympy  # noqa: F401
    except ImportError:
        print(
            'SymPy is not installed in the active Python environment. '
            'Install sympy locally (e.g. `python3 -m pip install sympy`) to '
            'generate temporary stress-test expressions.',
            file=sys.stderr,
        )
        return 1

    cases = build_expressions(args.count, args.seed)
    write_corpus_files(output_dir, cases)
    print(f'Generated {len(cases)} temporary SymPy cases in {output_dir.relative_to(repo_root)}.')

    if args.skip_oracle:
        return 0

    oracle_output = run_oracle(repo_root, cases)
    results = oracle_output.get('results', [])
    accepted = sum(1 for item in results if item.get('accepted') is True)
    refused = len(results) - accepted
    summary_path = output_dir / 'oracle_summary.json'
    summary_path.write_text(json.dumps(oracle_output, indent=2) + '\n', encoding='utf-8')
    print(
        f'Oracle verified {len(results)} SymPy cases: '
        f'{accepted} accepted, {refused} refused.'
    )
    return 0 if refused == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
