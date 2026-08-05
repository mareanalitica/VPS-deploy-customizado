# 🔑 Primeiro Acesso SSH na VPS

[← Voltar para o Hub de Documentação](../README.md)

Guia passo a passo pra configurar acesso SSH por chave (sem senha) numa VPS
nova ou recém-resetada, antes de rodar qualquer coisa do Ansible. Depois
que o acesso por chave estiver funcionando, use a
[Colinha de Restart da VPS](./vps-restart-cheatsheet.md) pro dia a dia.

---

## Quando usar este guia

- Você acabou de provisionar uma VPS nova (Hostinger, ou qualquer provedor).
- Você fez um **reset de sistema operacional** pelo painel do provedor (isso
  apaga o disco inteiro, incluindo `~/.ssh/authorized_keys` — a VPS "esquece"
  todas as chaves que você tinha configurado antes).

Nos dois casos, o ponto de partida é o mesmo: você só tem a senha `root`
temporária que o provedor te deu (por e-mail ou no painel), e precisa trocar
isso por acesso via chave SSH antes de fazer qualquer outra coisa.

---

## Por que chave em vez de senha?

- É o que o Ansible espera (`ansible_ssh_private_key_file` no inventário) —
  sem chave configurada, todo `ansible-playbook` falha de cara.
- Mais seguro: sem senha pra forçar por brute-force, e a chave privada nunca
  sai da sua máquina.
- Combina com o hardening (`role: hardening`) que, mais adiante no processo,
  desativa login por senha via SSH — se você não tiver a chave configurada
  **antes** disso rodar, fica trancado pra fora da própria VPS.

---

## Passo 1 — Gerar sua chave SSH (se ainda não tiver uma)

Cada ambiente que você for usar pra acessar a VPS (Windows/Git Bash, WSL,
etc.) precisa da sua própria chave — **eles não compartilham `~/.ssh`
automaticamente**, mesmo que você use o mesmo nome de arquivo nos dois (ver
nota no final deste guia).

```bash
ssh-keygen -t ed25519 -f ~/.ssh/mare-deploy -C "mare-deploy"
```

Aceite o caminho padrão sugerido (já é o que o comando acima define) e pode
deixar a senha da chave (passphrase) em branco pra simplificar automação —
só faça isso se a chave privada ficar só na sua máquina de desenvolvimento,
nunca em um servidor compartilhado.

Confirme que a chave pública existe:
```bash
cat ~/.ssh/mare-deploy.pub
```

---

## Passo 2 — Limpar o `known_hosts` (só necessário em reset de SO)

Se a VPS já existia antes e você resetou o sistema operacional, ela gera
uma **chave de host** nova. Seu terminal vai recusar a conexão com
`REMOTE HOST IDENTIFICATION HAS CHANGED!` até você limpar a entrada antiga:

```bash
ssh-keygen -R IP_DA_MAQUINA
```
(troque pelo IP real da sua VPS). Rode isso em **cada terminal** que for
usar — de novo, Git Bash e WSL guardam `known_hosts` separadamente.

Pule este passo se for uma VPS nova que você nunca acessou antes.

---

## Passo 3 — Conectar com a senha temporária

```bash
ssh root@IP_DA_MAQUINA
```

Vai pedir confirmação (`yes`) pra aceitar a chave de host na primeira vez, e
depois a senha `root` que o provedor te deu. Se a conta do provedor já
"lembra" uma chave sua de antes, pode conectar direto sem pedir senha — tudo
bem, mas siga o Passo 4 mesmo assim pra garantir que a chave certa (a que o
Ansible vai usar) está autorizada.

---

## Passo 4 — Autorizar sua chave pública

Ainda dentro da sessão SSH conectada por senha (do Passo 3), adicione o
conteúdo do Passo 1 ao `authorized_keys`:

```bash
echo "COLE_AQUI_O_CONTEUDO_DO_.PUB" >> ~/.ssh/authorized_keys
```

Se você for usar **mais de um ambiente** (ex: Git Bash no Windows *e* WSL),
repita este passo com o `.pub` de cada um — são arquivos fisicamente
diferentes, mesmo com o mesmo nome (`mare-deploy.pub`), então cada um
precisa ser adicionado separadamente.

---

## Passo 5 — Testar acesso sem senha

Abra um terminal **novo** (não reaproveite a sessão de senha) e teste:

```bash
ssh -i ~/.ssh/mare-deploy root@IP_DA_MAQUINA exit; echo "resultado: $?"
```

Só prossiga se aparecer `resultado: 0` **sem** pedir senha nenhuma vez. Se
pedir senha, a chave não foi adicionada corretamente — volte ao Passo 4.

---

## Próximo passo

Com o acesso por chave confirmado, o SSH está pronto. Agora é rodar o
Ansible pra configurar o resto (Docker, stacks, hardening) — veja o
**Cenário 2** da [Colinha de Restart da VPS](./vps-restart-cheatsheet.md)
pro comando exato e a ordem certa (hardening roda **por último**, de
propósito, pra não travar o próprio acesso SSH no meio do processo).

---

## Nota: por que Git Bash e WSL têm chaves diferentes

Mesmo rodando na mesma máquina Windows, o Git Bash e o WSL enxergam
sistemas de arquivos `~/.ssh` **fisicamente separados**:

| Ambiente | Caminho real de `~/.ssh` |
|---|---|
| Git Bash (Windows) | `C:\Users\<usuário>\.ssh` |
| WSL (Ubuntu) | `/home/<usuário>/.ssh` (dentro do filesystem Linux, não em `/mnt/c/...`) |

Gerar uma chave em um dos dois **não** cria a mesma chave no outro, mesmo
usando o mesmo comando com o mesmo nome de arquivo. Se você usa os dois
ambientes pra acessar a VPS (por exemplo, Git Bash pra uso manual e WSL pra
rodar o Ansible), repita os Passos 1 e 4 nos dois.