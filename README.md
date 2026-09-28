# zapret2-openwrt 🛡️🎮

[![OpenWrt Version](https://img.shields.io/badge/OpenWrt-23.05%20%7C%2024.10%20%7C%2025.12%2B-green?style=flat-square&logo=openwrt)](https://openwrt.org)
[![AmneziaWG](https://img.shields.io/badge/AmneziaWG-v3.1%20Obfuscated%20WARP-blue?style=flat-square)](https://amnezia.org)
[![Architecture](https://img.shields.io/badge/Arch-aarch64%20%7C%20x86__64%20%7C%20arm%20%7C%20mips-orange?style=flat-square)](https://github.com/rock12/zapret2-openwrt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

**zapret2-openwrt** — универсальный автономный программный комплекс для роутеров OpenWrt, объединяющий глубокий обход блокировок **DPI (Zapret2 / nfqws2)**, низкопинговый туннель **Cloudflare WARP на базе AmneziaWG (AWG 2.0 / 3.1)** с обфускацией, прозрачный туннель **Telegram** и интуитивный веб-интерфейс **LuCI** с раздельными тумблерами для популярных онлайн-игр.

---

## ⚡ Ключевые возможности

### 🔄 1. Обход DPI нового поколения (Zapret2 / nfqws2)
- Ядро `nfqws2` с чистой мульти-сплит стратегией по TLS SNI (`--lua-desync=multisplit:payload=tls_client_hello:dir=out:pos=1,sniext+1:seqovl=1`).
- Восстанавливает работу **YouTube (до 4K 60fps без просадок и задержек)**, **Discord** (включая звонки, каналы и голосовой шлюз), **Twitter / X**, **Instagram**, торрент-трекеров и любых заблокированных сервисов.
- **FastPath Auto-Exclude:** Незаблокированные ресурсы идут напрямую через вашего провайдера на максимальной гигабитной скорости без очередей `NFQUEUE` и нагрузки на процессор роутера.

### 🤖 2. Автоподбор стратегий для сайтов (DPI Auto-Tuning & Learning)
- **Полная автономность:** больше не нужно вручную гадать параметры `--lua-desync` в терминале или искать конфиги на форумах под своего провайдера!
- **Умное тестирование на лету:**
  - Фоновый демон (`autolearn-cidr.sh` / `autotune.sh`) мониторит сетевые аномалии (сбросы TCP RST, таймауты TLS Handshake).
  - Если к какому-то сайту не подошла базовая стратегия, система автономно тестирует стек проверенных desync-атак (`multisplit`, `hostfakesplit`, `fake`, `multidisorder`, `fakedsplit`, различные сдвиги `pos`, `seqovl` и фейковые SNI-пейлоады).
  - Как только сайт успешно ответил (HTTP 200 / TLS Finished), система автоматически фиксирует победившую комбинацию для этого сайта и сохраняет в память службы.
- **Conntrack Scanner (Авто-детектор жестких IP-банов):**
  - Если ресурс заблокирован по IP «наглухо» (пакеты TCP SYN сбрасываются ТСПУ, и никакой DPI-десинк бессилен, как с Railway Anycast), сканер мгновенно фиксирует это и бесшовно заворачивает проблемную подсеть в туннель Cloudflare WARP.

### 🎮 3. Игровой туннель Cloudflare WARP на базе AmneziaWG
- Полноценная поддержка протокола **AmneziaWG** с защитой от блокировок WireGuard со стороны ТСПУ в РФ (`Jc`, `Jmin`, `Jmax`, `H1-H4`, `I1`).
- **Персональные тумблеры (ВКЛ / ВЫКЛ)** прямо в веб-интерфейсе для каждой игры:
  - 🔘 **Call of Duty: Warzone & Modern Warfare** (серверные подсети)
  - 🔘 **Battlefield 6 / 2042 (EA DICE)**
  - 🔘 **Steam** (голосовые чаты и игровые серверы без лишнего трафика загрузок)
  - 🔘 **EA App / Origin**
  - 🔘 **Battle.net / Blizzard**
  - 🔘 **Epic Games & Fortnite**
  - 🔘 **Riot Games & Valorant**
  - 🔘 **Apex Legends & Rocket League**
  - 🔘 **Ubisoft / Rainbow Six Siege**
  - 🔘 **Roblox**
  - 🔘 **League of Legends**
  - 🔘 **Warframe**
  - 🔘 **Dead By Daylight**, **Arma Reforger**, **Minecraft** и др.
- Кнопка **`[ View / Edit ]`** позволяет в браузере просматривать или добавлять свои игровые подсети и IP-адреса.

### 🎯 4. WARP Scout (Автоподбор минимального игрового пинга)
- Роутер самостоятельно опрашивает десятки серверов Cloudflare с вашей интернет-линии и выбирает эндпоинт с **минимальным пингом** (от 20 мс) и нулевой потерей пакетов.

### ✈️ 5. Прозрачный туннель для Telegram
- Встроенный клиент `tg-mtproxy-client` (WebSocket TLS) и `tg-ws-proxy-go` (порт 2080).
- Автоматически прозрачно перенаправляет трафик Telegram через nftables: **мессенджер работает на всех смартфонах, ПК и Smart TV в домашней сети без необходимости включать прокси на самих устройствах**.
- Не конфликтует с внешними клиентами (Happ, Xray, Sing-Box, Shadowrocket, V2Ray).

---

## 💾 Сколько места и ресурсов занимает

Комплекс спроектирован для максимальной экономии ресурсов роутера:

| Компонент | Память Flash (ROM) | ОЗУ (RAM) | Нагрузка на CPU |
|---|---|---|---|
| **Ядро Zapret2** (`nfqws2`, lua, списки хостов) | ~2.2 МБ | ~8–12 МБ | < 1% (FastPath разгрузка) |
| **AmneziaWG** (модуль ядра `kmod-amneziawg` + утилиты) | ~0.15 МБ | ~1–2 МБ | 0% (работает в ядре Linux) |
| **Веб-интерфейс LuCI** (`luci-app-zapret2`) | ~0.12 МБ | 0 МБ (статика) | 0% |
| **Telegram WebSocket Client** (`tg-mtproxy-client`) | ~5.6 МБ | ~8–12 МБ | < 0.5% |
| **Telegram WebSocket Proxy** (`tg-ws-proxy-go`) | ~6.2 МБ | ~8–10 МБ | < 0.5% |
| **ИТОГО (базовый комплект: Zapret2 + WARP + LuCI)** | **~3–4 МБ** | **~15–20 МБ** | **Минимальная** |
| **ИТОГО (полный комплект со всеми прокси Telegram)** | **~14–16 МБ** | **~25–35 МБ** | **< 2%** |

> [!TIP]
> Комплекс отлично работает даже на бюджетных роутерах с **128 МБ RAM** и **32 МБ Flash**.

---

## 🚀 Быстрая установка (в 1 команду)

Подключитесь к роутеру по SSH (`ssh root@192.168.1.1`) и выполните команду:

```sh
curl -sSL https://raw.githubusercontent.com/rock12/zapret2-openwrt/zap1/install.sh | sh
```

*(Если утилита `curl` не установлена, выполните через `wget`:)*
```sh
wget -qO- https://raw.githubusercontent.com/rock12/zapret2-openwrt/zap1/install.sh | sh
```

### Системные зависимости (устанавливаются автоматически)
Скрипт проверяет и автоматически ставит все необходимые пакеты для вашего пакетного менеджера (`apk` или `opkg`):
- `curl`, `ca-bundle`, `ca-certificates` — для защищённой загрузки списков и конфигураций.
- `nftables`, `kmod-nft-core`, `kmod-nft-nat`, `kmod-nft-queue`, `kmod-nf-conntrack` — ядро фильтрации трафика и очереди NFQUEUE для `nfqws2`.
- `ip-full` — для расширенных политик маршрутизации (PBR, fwmark, отдельные таблицы).
- `bind-tools` — утилиты проверки доменов и DNS-резолвинга.
- `kmod-amneziawg`, `amneziawg-tools` — модуль ядра и тулзы AmneziaWG (если их нет в стандартных репозиториях OpenWrt, скрипт автоматически ставит их из репозитория Slava-Shchipunov).
- `https-dns-proxy` и `luci-app-https-dns-proxy` — DoH шифрование DNS-запросов для защиты от перехвата провайдером.

---

## 🖥️ Как пользоваться и менять стратегии в LuCI

### 1. Доступ к веб-интерфейсу
1. В браузере перейдите по адресу: **`http://192.168.1.1`**
2. В верхнем меню откройте: **Службы** → **Zapret 2**

### 2. Вкладка «Cloudflare WARP (Games)»
- **Enable Cloudflare WARP Tunnel** — мастер-тумблер игрового туннеля (по умолчанию включён).
- **Route Telegram via WARP** — прозрачная маршрутизация Telegram.
- **Scout Endpoint** — кнопка сканирования серверов Cloudflare для выбора эндпоинта с минимальной задержкой.
- **Игровые тумблеры** — включайте и отключайте маршрутизацию для каждой конкретной игры в 1 клик.

### 3. Как правильно менять стратегию в LuCI (Важно!)
Поле со стратегией `NFQWS2_OPT` в веб-интерфейсе сделано **только для чтения** (`readonly`), чтобы длинные параметры не нарушали верстку:
1. Нажмите кнопку **«Редактировать» (Edit)** рядом со строкой `NFQWS2_OPT`.
2. В открывшемся всплывающем окне внесите или вставьте нужную стратегию.
3. **Обязательно нажмите кнопку «Сохранить» (Save)** *внутри этого окна*.
4. Окно закроется, а новая стратегия отобразится в поле.
5. Нажмите синюю кнопку **«Сохранить и применить» (Save & Apply)** в самом низу страницы LuCI.
> [!NOTE]
> Скрипт службы `zapret2` автоматически синхронизирует изменения в файл демона `/opt/zapret2/config` и перезапускает `nfqws2` на лету.

---

## 🛠️ Полезные команды терминала (CLI)

| Команда | Описание |
|---|---|
| `/opt/zapret2/warp.sh status` | Показать статус подключения WARP и текущий эндпоинт |
| `/opt/zapret2/warp.sh scout` | Найти и включить сервер Cloudflare с минимальным пингом |
| `/opt/zapret2/warp.sh reload` | Перезагрузить правила фаервола для игр без рестарта службы |
| `/opt/zapret2/autotune.sh <домен>` | Запустить автоматический подбор рабочей стратегии под конкретный сайт |
| `/opt/zapret2/autolearn-cidr.sh list` | Показать список автоматически изученных доменов и подсетей |
| `tail -f /tmp/autolearn.log` | Просмотр журнала автоподбора доменов в реальном времени |
| `cat /tmp/zapret2-warp.log` | Просмотр лога игрового туннеля WARP |
| `/etc/init.d/zapret2 reload` | Мгновенная синхронизация настроек и перезапуск `nfqws2` |
| `/opt/zapret2/uninstall.sh` | Полное удаление комплекса с роутера |

---

## 🗑️ Полное удаление комплекса

Если вам потребуется удалить комплекс, достаточно выполнить одну команду:

```sh
curl -sSL https://raw.githubusercontent.com/rock12/zapret2-openwrt/zap1/uninstall.sh | sh
```

Либо запустить локальный скрипт на роутере:
```sh
/opt/zapret2/uninstall.sh
```

### Что делает скрипт удаления:
- Полностью останавливает и отключает службы `zapret2`, `warp`, `tg-tunnel`, `tg-ws-proxy`.
- Удаляет все правила `nftables`, таблицы `zapret`/`warp` и правила PBR (`fwmark`, таблица 100).
- Удаляет каталог `/opt/zapret2`, файлы веб-интерфейса LuCI, init-скрипты и бинарники.
- Восстанавливает оригинальные настройки DNS в `dnsmasq` и сбрасывает конфигурацию UCI.
- Перезапускает веб-сервер роутера. Роутер возвращается в исходное состояние "из коробки" без перезагрузки.

---

## 🙏 Спасибо авторам и разработчикам

Создание этого универсального комплекса стало возможным благодаря труду выдающихся разработчиков Open Source сообщества:

- **[bol-van](https://github.com/bol-van)** — автор легендарного проекта **[zapret](https://github.com/bol-van/zapret)** и инструмента **`nfqws` / `nfqws2`**, без которого обход DPI был бы невозможен.
- **[remittor](https://github.com/remittor)** — автор адаптации **zapret-openwrt** под платформу OpenWrt и оригинального веб-интерфейса **`luci-app-zapret`**.
- **[Dushnilin](https://github.com/Dushnilin)** — автор форка **zapret2-openwrt** v1.0.5.2 с интеграцией `nfqws2`.
- **[Slava-Shchipunov](https://github.com/Slava-Shchipunov)** — автор и мейнтейнер репозитория **[awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt)**, обеспечивающего готовые модули ядра `kmod-amneziawg` под любые релизы и архитектуры OpenWrt.
- **Команда [Amnezia VPN](https://amnezia.org)** — создатели протокола **AmneziaWG**, спасшего технологию WireGuard в условиях жесткой цензуры.
- **[Cloudflare](https://www.cloudflare.com)** — за глобальную высокоскоростную сеть WARP Anycast.
- **[necronicle](https://github.com/necronicle)** — за дополнительные библиотеки и наработки модуля `z2k`.

---

## 📜 Лицензия
Проект распространяется под лицензией **MIT License**.
