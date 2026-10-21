#!/usr/bin/env python3
"""Gerador de eventos de corrida — Lab 01, Aula 03.

Produz o dado que a startup de mobilidade produziria: uma linha JSON por
corrida, gravada em raw/corridas/dt=AAAA-MM-DD/parte-0001.json.

A janela termina no dia de hoje, então a última partição é sempre dt=<hoje> e
nenhuma data fica presa no repositório. Com a mesma --seed, a mesma --taxa e o
mesmo número de --dias, a saída é byte a byte igual em qualquer data.

    python3 app/gerador-eventos.py --dias 30 --taxa 12 --seed 42 --saida ./saida

Python 3.10 ou superior, sem dependência externa.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import sys
from pathlib import Path

# ---------------------------------------------------------------- o cenário

# Bairros do Recife e da Região Metropolitana, com o peso relativo de cada um
# na demanda. Boa Viagem concentra corrida porque concentra escritório e hotel.
BAIRROS: list[tuple[str, float]] = [
    ("Boa Viagem", 18.0),
    ("Pina", 7.5),
    ("Recife Antigo", 6.0),
    ("Ilha do Leite", 5.5),
    ("Espinheiro", 5.0),
    ("Graças", 5.0),
    ("Madalena", 4.8),
    ("Casa Forte", 4.5),
    ("Torre", 4.0),
    ("Boa Vista", 4.0),
    ("Derby", 3.6),
    ("Aflitos", 3.4),
    ("Santo Amaro", 3.2),
    ("Encruzilhada", 3.0),
    ("Imbiribeira", 3.0),
    ("Cordeiro", 2.8),
    ("Tamarineira", 2.6),
    ("Caxangá", 2.4),
    ("Várzea", 2.4),
    ("Bongi", 2.0),
    ("Setúbal", 4.0),
    ("Jaqueira", 3.3),
]

# Curva de demanda por hora do dia, em peso relativo. Dois picos: o da manhã,
# entre 7h e 9h, e o do fim de tarde, entre 17h e 19h. A madrugada não zera —
# é justamente ela que a pergunta de negócio deste semestre investiga.
CURVA_HORA: list[float] = [
    0.55, 0.42, 0.34, 0.30, 0.32, 0.48,  # 00h–05h
    0.95, 1.70, 2.05, 1.60, 1.15, 1.10,  # 06h–11h
    1.25, 1.20, 1.05, 1.05, 1.30, 1.95,  # 12h–17h
    2.00, 1.55, 1.20, 1.05, 0.90, 0.72,  # 18h–23h
]

# Proporção de eventos em que o produtor manda `valor` como texto com vírgula
# decimal, no lugar do número. É a sujeira plantada, e ela é conteúdo: o
# Crawler infere `double` a partir dos outros 98,5% e esses registros viram
# nulo, sem que nada avise.
FRACAO_VALOR_TEXTO = 0.015


# --------------------------------------------------------------- utilidades

def pesos_normalizados(curva: list[float]) -> list[float]:
    """Devolve a curva reescalada para média 1,0.

    É isto que faz `--taxa` ser a média de eventos por minuto, e não o pico:
    sem a normalização, `--taxa 12` entregaria mais eventos do que o número
    prometido no slide.
    """
    media = sum(curva) / len(curva)
    return [c / media for c in curva]


def reparte(total: int, pesos: list[float]) -> list[int]:
    """Distribui `total` inteiros entre as fatias, proporcional aos pesos.

    O resto é distribuído pelas maiores frações, de forma determinística, para
    que a soma feche exatamente em `total` — sem isso o número de eventos do
    dia dependeria de arredondamento e a demo deixaria de ser repetível.
    """
    soma = sum(pesos)
    exatos = [total * p / soma for p in pesos]
    base = [int(v) for v in exatos]
    falta = total - sum(base)
    ordem = sorted(range(len(pesos)), key=lambda i: (-(exatos[i] - base[i]), i))
    for i in ordem[:falta]:
        base[i] += 1
    return base


def escolhe_bairro(rnd: random.Random, acumulado: list[float], nomes: list[str]) -> str:
    alvo = rnd.random() * acumulado[-1]
    lo, hi = 0, len(acumulado) - 1
    while lo < hi:
        meio = (lo + hi) // 2
        if acumulado[meio] < alvo:
            lo = meio + 1
        else:
            hi = meio
    return nomes[lo]


# ------------------------------------------------------------------ geração

def gera(dias: int, taxa: int, seed: int, saida: Path) -> dict:
    rnd = random.Random(seed)
    nomes = [b for b, _ in BAIRROS]
    acumulado: list[float] = []
    corrente = 0.0
    for _, peso in BAIRROS:
        corrente += peso
        acumulado.append(corrente)

    curva_hora = pesos_normalizados(CURVA_HORA)
    hoje = dt.date.today()
    primeiro_dia = hoje - dt.timedelta(days=dias - 1)

    destino = saida / "raw" / "corridas"
    destino.mkdir(parents=True, exist_ok=True)

    corrida = 0
    total_bytes = 0
    total_eventos = 0
    valores_texto = 0
    particoes: list[tuple[str, int, int]] = []

    for offset in range(dias):
        dia = primeiro_dia + dt.timedelta(days=offset)
        # Todo dia recebe exatamente taxa x 1440 eventos. A curva de demanda
        # redistribui esses eventos entre as horas, e não entre os dias: é isso
        # que faz o full scan custar 30 vezes uma partição, em qualquer data em
        # que o laboratório for executado.
        eventos_do_dia = taxa * 1440
        por_hora = reparte(eventos_do_dia, curva_hora)

        pasta = destino / f"dt={dia.isoformat()}"
        pasta.mkdir(parents=True, exist_ok=True)
        arquivo = pasta / "parte-0001.json"

        bytes_do_dia = 0
        with arquivo.open("w", encoding="utf-8", newline="\n") as fh:
            for hora, quantidade in enumerate(por_hora):
                for _ in range(quantidade):
                    corrida += 1
                    minuto = rnd.randrange(60)
                    segundo = rnd.randrange(60)
                    inicio = dt.datetime(
                        dia.year, dia.month, dia.day, hora, minuto, segundo,
                        tzinfo=dt.timezone.utc,
                    )
                    distancia = round(rnd.lognormvariate(1.05, 0.62), 2)
                    distancia = min(distancia, 48.0)
                    # Velocidade média entre 14 e 34 km/h, conforme a hora.
                    velocidade = 14.0 + 20.0 * (1.0 - min(curva_hora[hora] / 2.05, 1.0))
                    duracao = round(max(3.0, distancia / velocidade * 60.0), 1)
                    fim = inicio + dt.timedelta(minutes=duracao)
                    valor = round(5.20 + distancia * 2.35 + duracao * 0.42, 2)

                    if rnd.random() < FRACAO_VALOR_TEXTO:
                        campo_valor: object = f"{valor:.2f}".replace(".", ",")
                        valores_texto += 1
                    else:
                        campo_valor = valor

                    evento = {
                        "corrida_id": f"c-{corrida:08d}",
                        "motorista_id": f"m-{rnd.randrange(1, 4200):05d}",
                        "passageiro_id": f"p-{rnd.randrange(1, 99999):05d}",
                        "bairro": escolhe_bairro(rnd, acumulado, nomes),
                        "data_corrida": inicio.strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "fim": fim.strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "distancia_km": distancia,
                        "duracao_min": duracao,
                        "valor": campo_valor,
                    }
                    linha = json.dumps(evento, ensure_ascii=False,
                                       separators=(", ", ":")) + "\n"
                    bytes_do_dia += len(linha.encode("utf-8"))
                    fh.write(linha)

        total_bytes += bytes_do_dia
        total_eventos += eventos_do_dia
        particoes.append((dia.isoformat(), eventos_do_dia, bytes_do_dia))

    return {
        "hoje": hoje.isoformat(),
        "particoes": particoes,
        "objetos": dias,
        "eventos": total_eventos,
        "bytes": total_bytes,
        "valores_texto": valores_texto,
        "destino": destino,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Gera eventos de corrida em JSON, particionados por dia.",
    )
    p.add_argument("--dias", type=int, default=30,
                   help="quantos dias de histórico gerar (padrão: 30)")
    p.add_argument("--taxa", type=int, default=12,
                   help="média de eventos por minuto, não o pico (padrão: 12)")
    p.add_argument("--seed", type=int, required=True,
                   help="semente do gerador; sem ela a demonstração não se repete")
    p.add_argument("--saida", type=Path, default=Path("./saida"),
                   help="diretório de saída (padrão: ./saida)")
    args = p.parse_args(argv)

    if args.dias < 1:
        p.error("--dias precisa ser 1 ou mais")
    if args.taxa < 1:
        p.error("--taxa precisa ser 1 ou mais")

    r = gera(args.dias, args.taxa, args.seed, args.saida)

    maior = max(r["particoes"], key=lambda t: t[2])
    hoje_part = [x for x in r["particoes"] if x[0] == r["hoje"]][0]

    print()
    print(f"destino ............. {r['destino']}")
    print(f"objetos ............. {r['objetos']}  (um por partição dt=)")
    print(f"eventos ............. {r['eventos']:,}".replace(",", "."))
    print(f"bytes ............... {r['bytes']:,}".replace(",", "."))
    print(f"maior partição ...... dt={maior[0]}  {maior[2]:,} bytes".replace(",", "."))
    print(f"partição de hoje .... dt={hoje_part[0]}  {hoje_part[2]:,} bytes".replace(",", "."))
    pct = 100.0 * r["valores_texto"] / r["eventos"]
    print(f"valor como texto .... {r['valores_texto']:,} eventos ({pct:.2f}%)".replace(",", "."))
    print()
    print("a linha WHERE do movimento 4, pronta para copiar:")
    print(f"    WHERE dt = '{r['hoje']}'")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
