"""Pipeline de vendas — evolução operacional do Ex1.

O Ex1 lia um CSV, validava e gerava um resumo. Este pipeline mantém a
mesma ideia, agora calculando total_amount a partir de quantity e unit_price.

A complexidade estudada neste exercício é operacional, não algorítmica.
"""

from __future__ import annotations

import os
from pathlib import Path

import pandas as pd

# Configuração de execução.
# Nenhum valor abaixo é específico de máquina ou é um segredo real: são apenas
# defaults neutros para desenvolvimento local. A execução real é sempre
# parametrizada por variáveis de ambiente (.env / docker-compose / Terraform).
# API_KEY nunca tem default aqui — segredo não tem valor de fallback no código.
INPUT_PATH = "data/input/sample.csv"
OUTPUT_PATH = "data/output/orders_transformed.csv"
ENVIRONMENT = "dev"
API_URL = "http://localhost:8080"
API_KEY = ""

REQUIRED_COLUMNS = {
    "order_id",
    "customer_id",
    "product",
    "quantity",
    "unit_price",
    "region",
}


def _setting(name: str, default: str) -> str:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return value


def load_orders(input_path: str | Path) -> pd.DataFrame:
    path = Path(input_path)
    if not path.exists():
        raise FileNotFoundError(f"Arquivo de entrada não encontrado: {path}")
    return pd.read_csv(path)


def validate_orders(df: pd.DataFrame) -> pd.DataFrame:
    missing = REQUIRED_COLUMNS - set(df.columns)
    if missing:
        raise ValueError(f"Colunas obrigatórias ausentes: {sorted(missing)}")

    required = df[list(REQUIRED_COLUMNS)]
    if required.isnull().any().any():
        raise ValueError("Valores nulos não são permitidos nas colunas obrigatórias")

    if (df["quantity"] <= 0).any():
        raise ValueError("quantity deve ser maior que zero")

    if (df["unit_price"] < 0).any():
        raise ValueError("unit_price não pode ser negativo")

    return df


def transform_orders(df: pd.DataFrame) -> pd.DataFrame:
    result = df.copy()
    result["total_amount"] = result["quantity"] * result["unit_price"]
    return result


def write_orders(df: pd.DataFrame, output_path: str | Path) -> Path:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False)
    return path


def notify_run(environment: str, rows: int, api_url: str, api_key: str) -> None:
    """Registra a intenção de notificar um serviço externo.

    Não faz chamada de rede: o laboratório deve permanecer executável
    sem um serviço auxiliar no localhost.
    """
    key_state = "present" if api_key else "absent"
    print(
        f"[notify] environment={environment} rows={rows} "
        f"url={api_url} api_key={key_state}"
    )


def run_pipeline(
    input_path: str | Path,
    output_path: str | Path,
    *,
    environment: str = "dev",
    api_url: str | None = None,
    api_key: str | None = None,
) -> pd.DataFrame:
    print(f"[pipeline] start environment={environment}")
    print(f"[pipeline] input={input_path}")
    print(f"[pipeline] output={output_path}")

    orders = load_orders(input_path)
    validate_orders(orders)
    transformed = transform_orders(orders)
    written = write_orders(transformed, output_path)

    total = float(transformed["total_amount"].sum())
    print(f"[pipeline] rows={len(transformed)}")
    print(f"[pipeline] regions={sorted(transformed['region'].unique())}")
    print(f"[pipeline] total_amount={total:.2f}")
    print(f"[pipeline] wrote={written}")

    notify_run(
        environment=environment,
        rows=len(transformed),
        api_url=api_url or API_URL,
        api_key=api_key if api_key is not None else API_KEY,
    )
    print("[pipeline] done")
    return transformed


def main() -> None:
    run_pipeline(
        _setting("INPUT_PATH", INPUT_PATH),
        _setting("OUTPUT_PATH", OUTPUT_PATH),
        environment=_setting("ENVIRONMENT", ENVIRONMENT),
        api_url=_setting("API_URL", API_URL),
        api_key=_setting("API_KEY", API_KEY),
    )


if __name__ == "__main__":
    main()
