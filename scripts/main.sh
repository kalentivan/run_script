#!/bin/bash

CONFIG_DIR="./config"
RUN_SCRIPT_URL="https://raw.githubusercontent.com/kalentivan/run_script/master/scripts/run.sh"

# Функция записи переменных в run.sh
# Добавляем CONTAINERS в ENV_VARS
ENV_VARS=(
  "FOLDER"
  "REPO"
  "NET"
  "IMAGE"
  "BASE_ENV"
  "BRANCH"
  "LOAD_DOCKER"
  "DEL_PROJECT"
  "CONTAINERS"
)

# Функция скачивания run.sh с запросом имени файла
download_run_script() {
  read -rp "Введите имя для скачанного скрипта (например, run.sh): " RUN_SCRIPT_NAME
  RUN_SCRIPT_PATH="./$RUN_SCRIPT_NAME"

  echo "⬇️ Скачиваем скрипт в файл $RUN_SCRIPT_PATH ..."
  curl -fsSL "$RUN_SCRIPT_URL" -o "$RUN_SCRIPT_PATH"
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка скачивания $RUN_SCRIPT_PATH"
    exit 1
  fi
  echo "✅ Скрипт скачан как $RUN_SCRIPT_PATH"
}

# Функция запроса имени .env файла и создание шаблона при отсутствии
ask_env_name() {
  read -rp "Введите название для .env файла (будет создан $CONFIG_DIR/<название>.env): " ENV_NAME
  ENV_PATH="$CONFIG_DIR/${ENV_NAME}.env"
  mkdir -p "$CONFIG_DIR"

  if [ ! -f "$ENV_PATH" ]; then
    echo "Файл $ENV_PATH не найден, создаём шаблон с переменными..."
    {
      echo "# Файл с переменными окружения для run.sh"
      for var in "${ENV_VARS[@]}"; do
        # BASE_ENV оставляем пустым, он будет заполнен позже
        if [ "$var" = "BASE_ENV" ]; then
          echo "$var="
        else
          echo "$var="
        fi
      done
    } > "$ENV_PATH"
  else
    echo "Файл $ENV_PATH найден и будет использован."
  fi
}

# Функция редактирования .env файла или поочередного запроса переменных
edit_or_fill_env_file() {
  read -rp "📝 Хотите заполнить $ENV_PATH сейчас? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Открываю $ENV_PATH в nano через 1 секунду..."
    sleep 1
    ${EDITOR:-nano} "$ENV_PATH"
  else
    echo "Поочерёдно заполните значения переменных:"
    for var in "${ENV_VARS[@]}"; do
      # Пропускаем BASE_ENV - он будет задан в run.sh
      if [ "$var" = "BASE_ENV" ]; then
        continue
      fi

      # Текущие значение из файла
      current_value=$(grep -E "^$var=" "$ENV_PATH" | head -1 | cut -d '=' -f2-)

      read -rp "$var [текущее: $current_value]: " input_value
      input_value="${input_value:-$current_value}"

      if grep -q "^$var=" "$ENV_PATH"; then
        sed -i "s|^$var=.*|$var=$input_value|" "$ENV_PATH"
      else
        echo "$var=$input_value" >> "$ENV_PATH"
      fi
    done
  fi
}

# Функция извлечения переменных из скачанного run.sh (если нужна)
extract_vars_from_run() {
  VARS=($(grep -oP '^\s*export\s+\K[A-Z0-9_]+(?==)' "$RUN_SCRIPT_PATH" | sort -u))
  if [ ${#VARS[@]} -eq 0 ]; then
    echo "⚠️ Не удалось найти переменные окружения в $RUN_SCRIPT_PATH"
  fi
}

# Функция запроса контейнеров, пока не введут 'n'
ask_containers() {
  local containers=()
  while true; do
    read -rp "Введите имя контейнера для добавления (или 'n' для завершения): " c
    if [[ "$c" == "n" ]]; then
      break
    elif [[ -n "$c" ]]; then
      containers+=("$c")
    fi
  done
  # Возвращаем список контейнеров через пробел
  echo "${containers[*]}"
}

# В функции edit_or_fill_env_file добавляем заполнение CONTAINERS
edit_or_fill_env_file() {
  read -rp "📝 Хотите заполнить $ENV_PATH сейчас? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Открываю $ENV_PATH в nano через 1 секунду..."
    sleep 1
    ${EDITOR:-nano} "$ENV_PATH"
  else
    echo "Поочерёдно заполните значения переменных:"
    for var in "${ENV_VARS[@]}"; do
      # Пропускаем BASE_ENV - он будет задан в run.sh
      if [ "$var" = "BASE_ENV" ]; then
        continue
      fi

      # Текущие значение из файла
      current_value=$(grep -E "^$var=" "$ENV_PATH" | head -1 | cut -d '=' -f2-)

      # Для CONTAINERS запускаем отдельный ввод
      if [ "$var" = "CONTAINERS" ]; then
        echo "Текущие контейнеры: $current_value"
        echo "Начинаем ввод контейнеров (вводите 'n' для окончания):"
        containers_input=$(ask_containers)
        input_value="${containers_input:-$current_value}"
      else
        read -rp "$var [текущее: $current_value]: " input_value
        input_value="${input_value:-$current_value}"
      fi

      if grep -q "^$var=" "$ENV_PATH"; then
        sed -i "s|^$var=.*|$var=$input_value|" "$ENV_PATH"
      else
        echo "$var=$input_value" >> "$ENV_PATH"
      fi
    done
  fi
}

# Добавляем обработку CONTAINERS в fill_vars_in_run
fill_vars_in_run() {
  local base_env_value="$1"

  declare -A VARS_DESC=(
    ["FOLDER"]="📁 Укажите папку для проекта"
    ["REPO"]="🔗 Укажите ссылку на репозиторий"
    ["NET"]="🌐 Укажите название Docker-сети"
    ["IMAGE"]="🐳 Укажите название Docker-образа"
    # BASE_ENV пропускаем запрос
    ["BRANCH"]="🌿 Укажите название ветки Git"
    ["LOAD_DOCKER"]="⚙️ Установить Docker? (y/n)"
    ["DEL_PROJECT"]="🧹 Удалить текущую папку проекта? (y/n)"
    ["CONTAINERS"]="📦 Укажите список контейнеров через пробел"
  )

  for var in "${!VARS_DESC[@]}"; do
    current_value=$(grep -oP "^export $var=\K.*" "$RUN_SCRIPT_PATH" | head -1 | tr -d '"')
    read -rp "${VARS_DESC[$var]} [текущее: $current_value]: " input_value
    input_value="${input_value:-$current_value}"
    if grep -q "^export $var=" "$RUN_SCRIPT_PATH"; then
      sed -i "s|^export $var=.*|export $var=\"$input_value\"|" "$RUN_SCRIPT_PATH"
    else
      echo "export $var=\"$input_value\"" >> "$RUN_SCRIPT_PATH"
    fi
  done

  # Записываем BASE_ENV без запроса
  if grep -q "^export BASE_ENV=" "$RUN_SCRIPT_PATH"; then
    sed -i "s|^export BASE_ENV=.*|export BASE_ENV=\"$base_env_value\"|" "$RUN_SCRIPT_PATH"
  else
    echo "export BASE_ENV=\"$base_env_value\"" >> "$RUN_SCRIPT_PATH"
  fi
}

make_run_executable() {
  chmod +x "$RUN_SCRIPT_PATH"
}

main() {
  download_run_script
  ask_env_name
  edit_or_fill_env_file
  extract_vars_from_run
  fill_vars_in_run "$ENV_PATH"
  make_run_executable

  echo -e "\n✅ Скрипт $RUN_SCRIPT_PATH готов к запуску."
  echo "📁 Ваш файл конфигурации: $ENV_PATH"
  echo "Для запуска используйте $RUN_SCRIPT_PATH"
}

main "$@"
