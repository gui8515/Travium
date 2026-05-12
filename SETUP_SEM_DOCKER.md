# Setup local sem Docker

Este projeto pode rodar localmente com Nginx + PHP-FPM + MariaDB + Redis + Memcached.

## 1) Rodar setup automatico

No diretorio do projeto:

```bash
sudo DOMAIN=travium.local DB_PASS='TraviumMainDb_2026' ./scripts/setup-native.sh
```

Se o root do MariaDB tiver senha, inclua tambem:

```bash
sudo DOMAIN=travium.local DB_PASS='TraviumMainDb_2026' DB_ROOT_PASS='SUA_SENHA_ROOT' ./scripts/setup-native.sh
```

O script faz:
- instalacao de pacotes do ambiente
- instalacao do PHP 7.4 e extensoes necessarias
- instalacao do Composer
- import do `maindb.sql`
- criacao do `config.php` a partir de `config.sample.php`
- configuracao do Nginx com todos os subdominios

## 2) Ajustar hosts local

Adicione no `/etc/hosts`:

```text
127.0.0.1 clickteam.com.br www.clickteam.com.br install.clickteam.com.br api.clickteam.com.br cdn.clickteam.com.br voting.clickteam.com.br payment.clickteam.com.br s1.clickteam.com.br
```

## 3) Finalizar instalacao no browser

Abra:

```text
http://install.travium.local/?key=CHAVE_GERADA_PELO_SCRIPT
```

Depois de criar o primeiro mundo, ele ficara em algo como:

```text
http://s1.travium.local/
```

## 4) Rodar engine do mundo (quando existir)

Apos o installer criar `servers/s1`, execute:

```bash
php ./servers/s1/include/engine.php
```

Para manter em background, use `systemd` ou `supervisor`.
