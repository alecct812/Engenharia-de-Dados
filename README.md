# Engenharia de Dados — CESAR School

Laboratórios da disciplina de Engenharia de Dados, graduação em Ciência da Computação.

**Grupo 02** · Turma 2026-2

## Estrutura

Um diretório por laboratório, na raiz do repositório:

```
lab01/    Exercício 01 — o schema é seu
```

Cada laboratório entra por um pull request próprio. A evidência de execução vai colada
no corpo do PR, junto com o que os critérios de aceite pedem.

## Laboratórios

| Pasta | Assunto | Ferramenta |
| --- | --- | --- |
| `lab01` | Lake mínimo com o schema **declarado** em vez de inferido: `AWS::Glue::Table` e `AWS::Glue::Partition` escritos à mão, sem Crawler, e um teto de bytes por consulta no Athena | CloudFormation |

## Convenções

**Região.** Toda stack sobe em `us-east-1`. Preço e disponibilidade de serviço mudam
entre regiões, e o exercício só é comparável se a região for a mesma.

**Nada de credencial versionada.** O `.gitignore` da raiz bloqueia `cred.txt`, `.env`,
`*.pem`, `*.key` e afins. O histórico do git é permanente: um segredo commitado uma vez
continua acessível mesmo depois de apagado, então a barreira tem que estar antes do
commit, não depois.

**Dado gerado não é versionado.** Os geradores dos laboratórios produzem centenas de MB
a partir de uma semente. Guardamos a semente e o comando, não o resultado — quem quiser
reproduzir roda o gerador e obtém os mesmos bytes.

**A stack é derrubada ao fim de cada laboratório.** Recurso que sobrevive ao `destroy`
continua cobrando, e a conta é compartilhada com a turma inteira.
