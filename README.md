# zapret2-openwrt 🛡️🎮

[![OpenWrt Version](https://img.shields.io/badge/OpenWrt-23.05%20%7C%2024.10%20%7C%2025.12%2B-green?style=flat-square&logo=openwrt)](https://openwrt.org)
[![AmneziaWG](https://img.shields.io/badge/AmneziaWG-Obfuscated%20WARP-blue?style=flat-square)](https://amnezia.org)
[![Architecture](https://img.shields.io/badge/Arch-aarch64%20%7C%20x86__64%20%7C%20arm%20%7C%20mips-orange?style=flat-square)](https://github.com/rock12/zapret2-openwrt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

**zapret2-openwrt** — интеллектуальный программный комплекс для роутеров OpenWrt, объединяющий автономный обход блокировок **DPI (Zapret2 / nfqws2)** с низкопинговым игровым туннелем **Cloudflare WARP на базе AmneziaWG** и удобным веб-интерфейсом **LuCI**.

---

## ⚡ Ключевые возможности

### 🔄 1. Мульти-стратегия обхода DPI (Circular Rotator)
- Ядро `nfqws2` работает по кольцевому алгоритму: если провайдер или ТСПУ меняет поведение фильтров, система автоматически перебирает проверенные desync-стратегии.
- Восстанавливает работу **YouTube (вплоть до 4K 60fps без замедления)**, **Discord** (включая звонки и голосовые каналы), **Twitter / X**, **Instagram**, торрент-трекеров и свыше 97 000 заблокированных ресурсов.

### 🎮 2. Игровой туннель Cloudflare WARP на базе AmneziaWG
- Встроенный протокол **AmneziaWG** (`proto amneziawg`) с продвинутой обфускацией (`Jc`, `Jmin`, `Jmax`, `H1-H4`, `I1`). **Обходит блокировки WireGuard на уровне ТСПУ в РФ.**
- **Персональные тумблеры (ON / OFF)** прямо в веб-интерфейсе напротив каждой игры:
  - 🔘 **Call of Duty: Warzone & Modern Warfare** (772 серверные подсети)
  - 🔘 **Battlefield 6 / 2042 (EA DICE)**
  - 🔘 **Steam** (игровые серверы и голосовые чаты без забивания канала загрузками)
  - 🔘 **EA App / Origin**
  - 🔘 **Battle.net / Blizzard**
  - 🔘 **Epic Games & Fortnite**
  - 🔘 **Riot Games & Valorant**
  - 🔘 **Apex Legends & Rocket League**
  - 🔘 **Ubisoft / Rainbow Six Siege**
  - 🔘 **Roblox**
  - 🔘 **League of Legends**
  - 🔘 **Warframe**
  - 🔘 **Dead By Daylight**, **Arma Reforger**, **Minecraft Extra** и др.
- Кнопка **`[ View / Edit ]`** в один клик открывает список подсетей для просмотра или ручного добавления IP.

### 🎯 3. WARP Scout (Поиск минимального игрового пинга)
- Роутер самостоятельно опрашивает десятки серверов Cloudflare прямо с вашей линии и выбирает эндпоинт с **минимальной задержкой** (от 20 мс) и нулевой потерей пакетов.

### ⚡ 4. FastPath Auto-Exclude (Умная разгрузка роутера)
- Если ресурс открывается напрямую без цензуры (проверяется прямым HTTP-зондированием), система автоматически заносит его в `nozapret` (аппаратный FastPath).
- Трафик незаблокированных ресурсов идёт напрямую через вашего провайдера на полной гигабитной скорости без очередей `NFQUEUE` и нагрузки на процессор роутера.

### 🧲 5. Conntrack Scanner (Авто-детектор жестких IP-банов)
- Если ресурс заблокирован по IP наглухо (пакеты TCP SYN сбрасываются ТСПУ, как у Railway Anycast), фоновый демон роутера автоматически фиксирует это и бесшовно перенаправляет этот IP в туннель WARP.

### 🛡️ 6. Строгая защита Рунета
- Национальные зоны (`.ru`, `.su`, `.рф`, `.дети`), а также сервисы российских банков и Госуслуг строго исключены из перехвата и всегда работают напрямую с максимальной безопасностью.

---

## 🚀 Быстрая установка (в 1 команду)

Подключитесь к роутеру по SSH (`ssh root@192.168.1.1`) и выполните универсальную команду установки:

```sh
curl -sSL https://raw.githubusercontent.com/rock12/zapret2-openwrt/zap1/install.sh | sh
```

*(Если на роутере нет `curl`, используйте: `wget -qO- https://raw.githubusercontent.com/rock12/zapret2-openwrt/zap1/install.sh | sh`)*

### Что делает скрипт установки:
1. Автоматически определяет версию OpenWrt (`23.05`, `24.10` с `opkg` или `25.12+` с `apk`).
2. Устанавливает все необходимые пакеты (`curl`, `ca-certificates`, `nftables`, `kmod-nf-conntrack`, `amneziawg-tools`/`wireguard-tools`, `bind-tools`).
3. Разворачивает `zapret2`, сервисный демон `init.d`, скрипты автоподбора и обфусцированный конфиг WARP.
4. Устанавливает веб-интерфейс **LuCI** с раздельными тумблерами для игр.
5. Настраивает автозапуск при перезагрузке роутера (`/etc/init.d/zapret2 enable`).
6. Автоматически запускает **WARP Scout** и выбирает самый быстрый эндпоинт Cloudflare.

---

## 📖 Как пользоваться

### 1. Веб-интерфейс LuCI
1. Откройте в браузере страницу роутера: **`http://192.168.1.1`**
2. Перейдите в меню: **Службы** → **Zapret 2**

### 2. Вкладка «Cloudflare WARP (Games)»
- **Enable Cloudflare WARP Tunnel**: Главный переключатель туннеля (по умолчанию включен).
- **Route Telegram via WARP**: Прозрачная маршрутизация Telegram для разблокировки на всех устройствах в доме.
- **Scout Endpoint**: Кнопка для пересканирования и выбора сервера Cloudflare с минимальным пингом.
- **Индивидуальные тумблеры игр**:
  - Напротив каждой игры переключите тумблер в положение **ВКЛ** или **ВЫКЛ** (например, выключить Warzone и оставить включенным только Battlefield 6).
  - Нажмите кнопку **`[ View / Edit ]`**, если хотите просмотреть или добавить свои подсети IP.
  - Нажмите **«Сохранить и применить»** внизу страницы.

### 3. Вкладка «Общие настройки»
- Режим фильтрации: **`autohostlist`** (рекомендуется — сайты добавляются автоматически при первом обращении, если к ним обнаружены блокировки).
- Готовые стратегии обхода DPI: уже преднастроена сбалансированная мульти-стратегия с ротацией для обхода любых видов блокировок ТСПУ.

---

## 🛠️ Полезные команды терминала (CLI)

| Команда | Описание |
|---|---|
| `/opt/zapret2/warp.sh status` | Проверить статус туннеля WARP (подключение и текущий эндпоинт) |
| `/opt/zapret2/warp.sh scout` | Запустить тест пинга и переключиться на самый быстрый сервер |
| `/opt/zapret2/warp.sh reload` | Мгновенно перезагрузить правила маршрутизации игр без рестарта демона |
| `/opt/zapret2/autolearn-cidr.sh list` | Показать автоматически изученные домены и подсети CIDR |
| `tail -f /tmp/autolearn.log` | Просмотр журнала автоподбора доменов и IP в реальном времени |
| `cat /tmp/zapret2-warp.log` | Просмотр логов игрового туннеля WARP |
| `/etc/init.d/zapret2 restart` | Полный перезапуск всех компонентов zapret2 |

---

## 📁 Структура каталогов на роутере

- `/opt/zapret2/` — исполняемые файлы и управляющие скрипты:
  - `warp.sh` — менеджер туннеля Cloudflare WARP (AmneziaWG)
  - `autolearn-cidr.sh` — фоновый демон автоподбора, FastPath и conntrack-сканера
  - `comfunc.sh`, `init.d.sh` — системные функции инициализации OpenWrt
- `/opt/zapret2/warp/` — конфигурация туннеля:
  - `WARP.conf` — защищенный конфиг AmneziaWG с параметрами обфускации
  - `warp-endpoints.txt` — список IP-эндпоинтов для скаута пинга
  - `games/` — файлы со списками IP-подсетей для каждой игры
  - `games_user.txt` — пользовательский список IP для любых своих игр
- `/opt/zapret2/ipset/` — списки хостов:
  - `zapret-hosts-user.txt` — основной список заблокированных доменов
  - `zapret-hosts-user-exclude.txt` — список исключений (FastPath)
- `/www/luci-static/resources/view/zapret2/` — фронтенд веб-интерфейса LuCI.

---

## 📜 Лицензия и благодарности

- Лицензия: **MIT**.
- **[bol-van / zapret2](https://github.com/bol-van/zapret2)** — автор оригинального комплекса Zapret2 и утилиты `nfqws2`.
- **[remittor / zapret-openwrt](https://github.com/remittor/zapret-openwrt)** — автор адаптации под OpenWrt и базового интерфейса LuCI.
- **[AmneziaWG](https://amnezia.org)** — обфусцированный протокол WireGuard для пробития цензуры ТСПУ.
