#!/bin/bash
# ОБНОВЛЕНИЕ С ГИТА ПРОЕКТА

export BASE_ENV="/root/config/run.env"
export SSH_KEY_PATH="/root/.ssh/my_project_key"

# Значения по умолчанию
init() {
  # Цвета
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m'


  # Переменные в $BASE_ENV должны быть такими:
  # FOLDER=папка_проекта
  # REPO=ссылка_на_репозиторий
  # NET=название_сети
  # IMAGE=название_образа
  # BRANCH=ветка_git
  # LOAD_DOCKER=y/n
  # DEL_PROJECT=y/n
  # CONTAINERS="контейнер1,контейнер2,контейнер3" или пробелами

  if [ -f "$BASE_ENV" ]; then
    # shellcheck disable=SC1090
    source "$BASE_ENV"
  else
    echo -e "${RED}⚠️ Файл с переменными окружения $BASE_ENV не найден!${NC}"
    exit 1
  fi

  # Преобразуем строку CONTAINERS в массив, разделяя по запятым или пробелам
  # Сначала заменим запятые на пробелы, потом разобьём на массив
  IFS=', ' read -r -a CONTAINERS <<< "$CONTAINERS"
}

# Функция ошибки
error_exit() {
    echo -e "${RED}Ошибка: $1${NC}" >&2
    exit 1
}

# Установить докер
load_docker() {
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg lsb-release || error_exit "🛑 Не удалось установить зависимости"

  # Определяем версию Ubuntu
  UBUNTU_VERSION=$(lsb_release -cs)
  echo "🔍 Обнаружена версия Ubuntu: $UBUNTU_VERSION"

  # Проверка и установка Docker
  if ! command -v docker &>/dev/null; then
      echo "⬇️ Docker не установлен, начинаем установку..."
  else
      # Проверяем, установлен ли Docker через snap
      if command -v snap &>/dev/null && snap list | grep -q docker; then
          echo "🔄 Обнаружен Docker, установленный через snap - переустанавливаем через apt..."
          sudo snap remove docker --purge
          sudo rm -f /etc/apt/keyrings/docker.gpg
          sudo rm -f /etc/apt/sources.list.d/docker.list
      else
          echo "✅ Docker уже установлен (не через snap)"
          docker --version
      fi
  fi

  echo "🔑 Добавление ключа Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg || error_exit "Не удалось получить ключ Docker"
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "📄 Добавление репозитория Docker..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_VERSION stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update || error_exit "🛑 Не удалось обновить список пакетов"

  # Установка Docker через apt
  if ! command -v docker &>/dev/null; then
      echo "⬇️ Установка Docker..."
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error_exit "Не удалось установить Docker"
  fi

  # Проверка docker compose V2
  if ! docker compose version &>/dev/null; then
      echo "⬇️ Установка Compose V2 (plugin)..."
      sudo apt-get install -y docker-compose-plugin || error_exit "🛑 Не удалось установить docker compose plugin"
  else
      echo "✅ Docker Compose V2 уже установлен"
  fi

  # Запуск и enable Docker
  if ! systemctl is-active --quiet docker; then
      echo "▶️ Запуск Docker..."
      sudo systemctl start docker || error_exit "🛑 Не удалось запустить Docker"
      sudo systemctl enable docker
  else
      echo "✅ Docker уже запущен"
  fi

  echo -e "${GREEN}✅ Docker успешно установлен и настроен!${NC}"
}

# Вывести в консоль все аргументы
show_args() {
    # Вывод итоговых значений переменных
  echo -e "${GREEN}Используемые параметры:${NC}"
  echo -e "  📁 Папка проекта       : ${FOLDER}"
  echo -e "  🔗 Репозиторий         : ${REPO}"
  echo -e "  🌐 Docker-сеть         : ${NET}"
  echo -e "  🐳 Docker-образ        : ${IMAGE}"
  echo -e "  📄 .env-файл           : ${BASE_ENV}"
  echo -e "  🌿 Ветка Git           : ${BRANCH}"
  echo -e "  🌿 Удалить папку       : ${DEL_PROJECT}"
  echo -e "  🌿 Скачать докер       : ${LOAD_DOCKER}"
  echo -e "${GREEN}Контейнеры, которые будут использоваться:${NC}"
  for container in "${CONTAINERS[@]}"; do
      echo -e "  📦 $container"
  done
  echo -e ""
}

# Вывод флагов скрипта
usage() {
  echo -e "${GREEN}Использование: $0 [опции]${NC}"
  echo
  echo "Опции:"
  echo "  -f <folder>     Папка для проекта (по умолчанию: '$FOLDER')"
  echo "  -r <repo>       Ссылка на репозиторий (по умолчанию: '$REPO')"
  echo "  -n <net>        Название Docker-сети (по умолчанию: '$NET')"
  echo "  -i <image>      Название Docker-образа (по умолчанию: '$IMAGE')"
  echo "  -e <env>        Путь к .env-файлу на сервере (по умолчанию: '$BASE_ENV')"
  echo "  -b <branch>     Ветка Git (по умолчанию: '$BRANCH')"
  echo "  -h              Показать эту справку и выйти"
  echo "  -s <y|n>        Установить или пропустить установку Docker (по умолчанию: '$LOAD_DOCKER')"
  echo "  -d <y|n>        Удалить текущую папку проекта (по умолчанию: '$DEL_PROJECT')"
  echo -e ""
  show_args
  exit 0
}

# Парсинг аргументов
parse() {
  local help_triggered=false
  while getopts ":f:r:n:i:e:b:s:d:h" opt; do
    case $opt in
      f) FOLDER="$OPTARG" ;;
      r) REPO="$OPTARG" ;;
      n) NET="$OPTARG" ;;
      i) IMAGE="$OPTARG" ;;
      e) BASE_ENV="$OPTARG" ;;
      b) BRANCH="$OPTARG" ;;
      s) LOAD_DOCKER="$OPTARG" ;;
      d) DEL_PROJECT="$OPTARG" ;;
      h)
        help_triggered=true
        usage
        ;;
      \?)
        echo -e "${RED}❌ Неизвестный параметр: -$OPTARG${NC}" >&2
        usage
        exit 1
        ;;
      :)
        echo -e "${RED}❌ Опция -$OPTARG требует аргумент.${NC}" >&2
        usage
        exit 1
        ;;
    esac
  done
  # Выход после обработки всех аргументов, если была вызвана справка
  if [ "$help_triggered" = true ]; then
    show_args
    exit 0
  fi
}

# Остановить контейнер
stop_container() {
  local container="$1"
  if [ "$(docker ps -q -f name="$container")" ]; then
    echo "🛑 Остановка контейнера $container..."
    docker stop "$container" || error_exit "🛑 Не удалось остановить контейнер $container"
  fi
  if [ "$(docker ps -aq -f name="$container")" ]; then
    echo "🗑️ Удаление контейнера $container..."
    docker rm "$container" || error_exit "🛑 Не удалось удалить контейнер $container"
  fi
}

# Функция для выполнения Git-операции с повторными попытками
git_with_retry() {
  local max_attempts=3
  local attempt=1
  local success=false

  while [ $attempt -le $max_attempts ]; do
      if "$@"; then
          success=true
          break
      else
          echo "⚠️ Попытка $attempt из $max_attempts не удалась. Повторяем через 2 секунды..."
          sleep 2
          ((attempt++))
      fi
  done

  if [ "$success" = false ]; then
      error_exit "🛑Не удалось выполнить Git-операцию после $max_attempts попыток"
  fi
}

# Обновить с гита
git_update() {
  if [ -n "$SSH_KEY_PATH" ]; then
    export GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o IdentitiesOnly=yes"
  fi
  if ! command -v git &>/dev/null; then
      echo "🛠 Установка Git..."
      sudo apt-get install -y git || error_exit "🛑Не удалось установить Git"
  fi

  if [ -d ".git" ] && [ -f ".git/config" ]; then
      echo "🔄 Репозиторий уже существует, обновляем..."

      git_with_retry git pull origin "$BRANCH"
  else
      if [ "$(ls -A .)" ]; then
          echo -e "${RED}❌ Каталог $FOLDER не пуст и не является git-репозиторием.${NC}"
          read -p "🔁 Удалить содержимое и клонировать заново? (y/N): " confirm
          if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
              echo "🧹 Удаление содержимого каталога $FOLDER..."
              rm -rf ./* .[^.]* 2>/dev/null
              echo "⬇️ Клонирование репозитория в $FOLDER..."
              git_with_retry git clone -b "$BRANCH" "$REPO" .
          else
              error_exit "⛔ Операция прервана пользователем. Очистите каталог вручную или укажите другой путь."
          fi
      else
          echo "⬇️ Клонирование репозитория в $FOLDER..."
          git_with_retry git clone -b "$BRANCH" "$REPO" .
      fi
  fi
}

# Собрать файл с переменными окружения
env_set() {
  # Путь к Python скрипту
  PYTHON_SCRIPT="./scripts/init_env.py"

  # Проверяем, существует ли Python скрипт
  if [ ! -f "$PYTHON_SCRIPT" ]; then
      echo "🛑 Python скрипт $PYTHON_SCRIPT не найден"
      exit 1
  fi

  # Проверяем, существует ли исходный .env файл
  if [ ! -f "$BASE_ENV" ]; then
      echo "🛑 Исходный файл "$BASE_ENV" не найден"
      exit 1
  fi

  # Проверяем, существует ли шаблон .env файла
  if [ ! -f "./scripts/.env.template" ]; then
      echo "🛑 Файл шаблона ./scripts/.env.template не найден"
      exit 1
  fi

  # Запускаем Python скрипт с аргументами
  python3 "$PYTHON_SCRIPT" --original "$BASE_ENV" --template "./scripts/.env.template" --output ".env"

  # Проверяем успешность выполнения
  if [ $? -eq 0 ]; then
      echo "✅ Файл .env успешно сгенерирован"
  else
      echo "🛑 Ошибка при генерации файла .env"
      # Копируем файл из сервера в папку проекта
      cp "$BASE_ENV" "./.env"
      echo "⚠️⚠️ Копируем файл $BASE_ENV из сервера в файл .env"
  fi

  ENV_FILE=".env"
}

# Запустить докер
start_docker() {
  # Проверка наличия Dockerfile
  if [ ! -f "Dockerfile" ]; then
      error_exit "🛑 Dockerfile не найден в репозитории!"
  fi

  # Сборка
  echo "🔨 Сборка Docker-образов..."
    docker build -t ${IMAGE} . || error_exit "🛑 Не удалось собрать Docker-образы"

  # Запуск
  echo "🚀 Запуск контейнеров..."
  docker compose up -d --force-recreate || error_exit "🛑 Не удалось запустить контейнеры"
  docker compose logs -f || error_exit "🛑 Не удалось запустить контейнеры"

  echo -e "${GREEN}✅ Проект успешно собран и запущен!${NC}"
  echo "✅🔗 FastAPI доступен"
}

# Удалит текущую папку проекта
rem_folder() {
  # Удалить папку для размещения проекта, если она ранее создана
  if [ -d "$FOLDER" ]; then
      read -p "🛑 Папка '$FOLDER' уже существует. Удалить её? [y/N]: " confirm
      case "$confirm" in
          [yY]|[нН])
              echo "🗑 Удаляю папку: $FOLDER"
              rm -rf "$FOLDER"
              echo "📁 Создание новой папки $FOLDER..."
              mkdir -p "${FOLDER}" || error_exit "🛑 Не удалось создать папку"
              ;;
          *)
              echo "🔄 Продолжаем работу с существующей папкой '$FOLDER'"
              ;;
      esac
  else
      echo "📁 Папка не существует: $FOLDER."
      mkdir -p "${FOLDER}" || error_exit "🛑 Не удалось создать папку"
      echo "✅ Папка $FOLDER создана"
  fi
}

# Создать сеть
init_net() {
  if ! docker network ls --format '{{.Name}}' | grep -qw "$NET"; then
    docker network create "$NET" || error_exit "Не удалось создать сеть Docker"
  else
    echo "⚠️ Сеть $NET уже существует"
  fi
}

main() {
  set -euo pipefail
  init
  parse "$@"
  show_args

  if [[ "$LOAD_DOCKER" =~ ^[yY]$ ]]; then
    load_docker
  fi

  echo -e "${GREEN}🔄 Остановка контейнеров...${NC}"
  for container in "${CONTAINERS[@]}"; do
    stop_container "$container" &
  done
  wait

  docker system prune -f || error_exit "🛑Не удалось очистить кеш"

  if [[ "$DEL_PROJECT" =~ ^[yY]$ ]]; then
    rem_folder  # удалит + создаст и зайдёт
  fi

  mkdir -p "$FOLDER" || error_exit "🛑 Не удалось создать папку $FOLDER"
  cd "$FOLDER" || error_exit "🛑 Не удалось перейти в папку $FOLDER"
  git_update      # клон или pull
  mkdir -p logs stat pgdata || error_exit "🛑Не удалось создать директории"
  init_net
  env_set
  start_docker
}

main "$@"
