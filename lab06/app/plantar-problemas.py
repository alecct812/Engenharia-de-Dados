#!/usr/bin/env python3
"""Planta, no cru gerado pelo gerador-eventos.py, os problemas do Ciclo 6.

O gerador do Lab 01 continua intocado: ele grava cada corrida na pasta do dia
em que ela aconteceu. Este script mexe só nos arquivos já gerados, para que o
cru passe a se comportar como um export de verdade:

  --atraso N     a madrugada (0h a 5h) de N dias atrás não chegou no export do
                 próprio dia: o servidor de borda caiu e as corridas ficaram no
                 celular dos motoristas. Elas saem de dt=<N dias atrás>/ e
                 chegam hoje, em dt=<hoje>/parte-0002-atrasadas.json.

  --reentrega N  o produtor reenviou o arquivo de N dias atrás: as mesmas
                 corridas chegam de novo no dia seguinte, em
                 dt=<N-1 dias atrás>/parte-0002-reenvio.json.

Na raw, dt é o DIA DE CHEGADA do arquivo. "Hoje" é a última pasta dt= que o
gerador criou, e não o relógio. Determinístico: mesma entrada, mesma saída.

    python3 app/plantar-problemas.py --saida /tmp/eda-a24 --atraso 3

Python 3.10 ou superior, sem dependência externa.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path


def hora(linha: str) -> int:
    return int(json.loads(linha)["data_corrida"][11:13])


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Planta dado atrasado e reentrega no cru.")
    p.add_argument("--saida", type=Path, required=True, help="a mesma --saida do gerador")
    p.add_argument("--atraso", type=int, default=3, help="dias de atraso da madrugada perdida (padrão: 3)")
    p.add_argument("--reentrega", type=int, default=0, help="dias atrás do arquivo reenviado (0 = sem reentrega)")
    a = p.parse_args(argv)

    raiz = a.saida / "raw" / "corridas"
    dias = sorted(x.name[3:] for x in raiz.glob("dt=*") if x.is_dir())
    if not dias:
        p.error(f"nada em {raiz}: rode o gerador-eventos.py antes")
    hoje = dt.date.fromisoformat(dias[-1])
    if (raiz / f"dt={hoje}" / "parte-0002-atrasadas.json").exists():
        p.error("o atraso já foi plantado nesta pasta; gere o cru de novo antes de plantar")

    # 1. ATRASO: a madrugada de hoje - N sai da pasta do próprio dia e chega hoje
    dia_atraso = hoje - dt.timedelta(days=a.atraso)
    orig = raiz / f"dt={dia_atraso}" / "parte-0001.json"
    linhas = orig.read_text(encoding="utf-8").splitlines(keepends=True)
    ficam = [l for l in linhas if hora(l) > 5]
    atrasadas = [l for l in linhas if hora(l) <= 5]
    orig.write_text("".join(ficam), encoding="utf-8")
    (raiz / f"dt={hoje}" / "parte-0002-atrasadas.json").write_text("".join(atrasadas), encoding="utf-8")

    print()
    print(f"hoje (última pasta) .... dt={hoje}")
    print(f"dado atrasado .......... {len(atrasadas):,} corridas da madrugada de {dia_atraso}".replace(",", "."))
    print(f"                         saíram de dt={dia_atraso}/ e chegaram em dt={hoje}/parte-0002-atrasadas.json")

    # 2. REENTREGA: o arquivo de hoje - N chega de novo no dia seguinte
    if a.reentrega:
        dia_r = hoje - dt.timedelta(days=a.reentrega)
        if dia_r == dia_atraso:
            p.error("--reentrega e --atraso não podem apontar para o mesmo dia")
        chegada = dia_r + dt.timedelta(days=1)
        texto = (raiz / f"dt={dia_r}" / "parte-0001.json").read_text(encoding="utf-8")
        (raiz / f"dt={chegada}" / "parte-0002-reenvio.json").write_text(texto, encoding="utf-8")
        n = texto.count("\n")
        print(f"reentrega .............. {n:,} corridas de {dia_r} chegaram de novo em dt={chegada}/parte-0002-reenvio.json".replace(",", "."))

    desde = hoje - dt.timedelta(days=6)
    print()
    print("as linhas para o Athena, prontas para copiar:")
    print(f"    WHERE dt >= '{desde}'          -- os últimos 7 dias")
    print(f"    WHERE dt = '{dia_atraso}'      -- o dia da madrugada atrasada")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
