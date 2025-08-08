#!/bin/bash

CONFIG_DIR="./config"
SCRIPT_DIR="./scripts"
RUN_SCRIPT_URL="https://raw.githubusercontent.com/kalentivan/run_script/master/scripts/run.sh"
RUN_SCRIPT_PATH="$SCRIPT_DIR/run.sh"

# Функция скачивания run.sh
download_run_script() {
  echo "⬇️ Скачиваем скрипт run.sh..."
  mkdir -p "$SCRIPT_DIR"
  curl -fsSL "$RUN_SCRIPT_URL" -o "$RUN_SCRIPT_PATH"
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка скачивания run.sh"
    exit 1
  fi
  echo "✅ run.sh скачан"
}

# Функция запроса имени .env файла
ask_env_name() {
  read -rp "Введите название для .env файла (будет создан $CONFIG_DIR/<название>.env): " ENV_NAME
  ENV_PATH="$CONFIG_DIR/${ENV_NAME}.env"
  mkdir -p "$CONFIG_DIR"
  if [ ! -f "$ENV_PATH" ]; then
    touch "$ENV_PATH"
  fi
}

# Функция открытия .env в nano
edit_env_file() {
  echo "📝 Открываем $ENV_PATH в nano для ввода данных..."
  nano "$ENV_PATH"
}

# Функция поиска переменных export в run.sh
extract_vars_from_run() {
  VARS=($(grep -oP '^\s*export\s+\K[A-Z0-9_]+(?==)' "$RUN_SCRIPT_PATH" | sort -u))
  if [ ${#VARS[@]} -eq 0 ]; then
    echo "⚠️ Не удалось найти переменные окружения в $RUN_SCRIPT_PATH"
  fi
}

# Функция заполнения переменных в .env
fill_vars_in_env() {
  if [ ${#VARS[@]} -eq 0 ]; then
    return
  fi
  echo "🖊️ Предлагаю заполнить значения для переменных из run.sh:"
  for var in "${VARS[@]}"; do
    current_value=$(grep -oP "export $var=\K.*" "$RUN_SCRIPT_PATH" | head -1 | tr -d '"')
    read -rp "Введите значение для $var [текущий: $current_value]: " input_value
    input_value="${input_value:-$current_value}"

    if grep -q "^$var=" "$ENV_PATH"; then
      sed -i "s|^$var=.*|$var=\"$input_value\"|" "$ENV_PATH"
    else
      echo "$var=\"$input_value\"" >> "$ENV_PATH"
    fi
  done
}

# Функция добавления прав на запуск для run.sh
make_run_executable() {
  chmod +x "$RUN_SCRIPT_PATH"
}

# Основная функция
main() {
  download_run_script
  ask_env_name
  edit_env_file
  extract_vars_from_run
  fill_vars_in_env
  make_run_executable

  echo -e "\n✅ Скрипт run.sh готов к запуску."
  echo "📁 Ваш файл конфигурации: $ENV_PATH"
  echo "Для запуска используйте $RUN_SCRIPT_PATH"
}

main "$@"
