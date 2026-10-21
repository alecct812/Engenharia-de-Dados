# Engenharia de Dados — CESAR School

Laboratórios da disciplina de Engenharia de Dados, graduação em Ciência da Computação.

**Grupo 02** · Turma 2026-2

## Estrutura

Um diretório por laboratório, na raiz do repositório:

```
lab01/    Exercício 01: o schema é seu
lab02/    Exercício 02: do zero em Terraform
lab03/    Exercício 03: refatorar em módulo, com plan limpo
lab04/    Exercício 04: a meta de custo, em Parquet particionado
```

Cada laboratório entra por um pull request próprio. A evidência de execução vai colada
no corpo do PR, junto com o que os critérios de aceite pedem.

## Laboratórios

| Pasta | Assunto | Ferramenta |
| --- | --- | --- |
| `lab01` | Lake mínimo com o schema **declarado** em vez de inferido: `AWS::Glue::Table` e `AWS::Glue::Partition` escritos à mão, sem Crawler, e um teto de bytes por consulta no Athena | CloudFormation |
| `lab02` | O mesmo lake construído **do zero**, com as decisões de schema, número de partições e teto de bytes tomadas e justificadas por nós, e `destroy` provado limpo | Terraform, state local |
| `lab03` | A stack plana refatorada em **módulo + backend remoto + workspace**, sem recriar um único recurso: `terraform state mv` e um `plan` que fecha em `No changes` | Terraform, state remoto com trava |
| `lab04` | A trusted em **Parquet particionado**, escrita por um job Glue, com uma **meta de custo** por consulta declarada e provada no Athena; o layout alternativo foi construído e medido antes da escolha | Terraform, Glue, Athena |

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

**State do Terraform não é versionado; o lock file é.** A partir do `lab02` o
provisionamento é em Terraform, e o `terraform.tfstate` fica de fora do repositório:
ele descreve a infraestrutura inteira e os enunciados proíbem versioná-lo. O
`.gitignore` bloqueia ele, o `.terraform/`, os planos binários e o `backend.hcl`, que
nomeia a conta. O `.terraform.lock.hcl`, ao contrário, **é** versionado: ele trava a
versão exata do provider, e sem ele um `~> 5.0` pode resolver para outra versão
amanhã e quebrar um `plan` que hoje fecha limpo.

**A stack é derrubada ao fim de cada laboratório.** Recurso que sobrevive ao `destroy`
continua cobrando, e a conta é compartilhada com a turma inteira.
