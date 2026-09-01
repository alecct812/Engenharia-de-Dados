#!/usr/bin/env python3
"""
Gera dados de corridas da startup, um arquivo JSON por dia, em pastas de
particao dt=AAAA-MM-DD. Cada dia tem volume suficiente (~3-4 MB) para que uma
consulta que varra varias particoes ultrapasse um teto proximo do piso, e uma
consulta de uma particao so passe.

Uso:
    python3 gerar-corridas.py --dias 8
    # cria dados/saida/dt=<dia>/parte-0001.json para os ultimos 8 dias (ate hoje)

Depois, suba tudo de uma vez:
    aws s3 cp dados/saida/ s3://SEU-BUCKET/raw/corridas/ --recursive
"""
import argparse, json, os, random, datetime

BAIRROS = ["Boa Viagem","Pina","Recife Antigo","Espinheiro","Casa Forte",
           "Madalena","Torre","Gracas","Boa Vista","Santo Amaro","Ilha do Leite",
           "Derby","Aflitos","Parnamirim","Encruzilhada"]

def gera_dia(dia, linhas, rnd):
    out = []
    for i in range(linhas):
        h = rnd.choice([0,1,2,3,4,0,1,2,3,23,22])   # peso na madrugada
        m = rnd.randint(0,59); dur = rnd.randint(5,42)
        reg = {
            "corrida_id":   f"c{dia.replace('-','')}{i:06d}",
            "motorista_id": f"m{rnd.randint(1,120):04d}",
            "passageiro_id":f"p{rnd.randint(1,4000):05d}",
            "bairro":       rnd.choice(BAIRROS),
            "data_corrida": f"{h:02d}:{m:02d}:00",
            "fim":          f"{(h)%24:02d}:{(m+dur)%60:02d}:00",
            "distancia_km": round(rnd.uniform(1.0,18.0),1),
            "duracao_min":  dur,
            "valor":        round(rnd.uniform(6.5,58.0),2),
        }
        out.append(json.dumps(reg, ensure_ascii=False))
    return "\n".join(out) + "\n"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dias", type=int, default=8, help="quantos dias, terminando hoje")
    ap.add_argument("--linhas", type=int, default=16000, help="linhas por dia (~3-4 MB)")
    ap.add_argument("--saida", default=os.path.join(os.path.dirname(__file__), "saida"))
    a = ap.parse_args()

    hoje = datetime.date.today()
    for k in range(a.dias):
        dia = (hoje - datetime.timedelta(days=k)).isoformat()
        rnd = random.Random(dia)                 # deterministico por dia
        pasta = os.path.join(a.saida, f"dt={dia}")
        os.makedirs(pasta, exist_ok=True)
        caminho = os.path.join(pasta, "parte-0001.json")
        with open(caminho, "w", encoding="utf-8") as f:
            f.write(gera_dia(dia, a.linhas, rnd))
        tam = os.path.getsize(caminho)
        print(f"dt={dia}  {a.linhas} linhas  {tam/1_000_000:.2f} MB  ->  {caminho}")

    print(f"\nPronto. {a.dias} particoes em {a.saida}/")
    print("Suba com:  aws s3 cp", a.saida + "/", "s3://SEU-BUCKET/raw/corridas/ --recursive")

if __name__ == "__main__":
    main()
