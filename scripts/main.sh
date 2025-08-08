#!/bin/bash

CONFIG_DIR="./config"
RUN_SCRIPT_URL="https://raw.githubusercontent.com/kalentivan/run_script/master/scripts/run.sh"
RUN_ENV_URL="https://raw.githubusercontent.com/kalentivan/run_script/master/scripts/run.env"

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

download_docker_env() {
  mkdir -p "$CONFIG_DIR"
  read -rp "Введите название для Docker .env файла (без расширения, например s): " DOCKER_ENV_NAME

  if [[ "$DOCKER_ENV_NAME" == *.env ]]; then
    DOCKER_ENV_PATH="$CONFIG_DIR/$DOCKER_ENV_NAME"
    DOCKER_ENV_NAME="${DOCKER_ENV_NAME%.env}"
  else
    DOCKER_ENV_PATH="$CONFIG_DIR/${DOCKER_ENV_NAME}.env"
  fi

  if [ -f "$DOCKER_ENV_PATH" ]; then
    echo "Файл $DOCKER_ENV_PATH уже существует и будет использован."
  else
    echo "Создаём пустой файл $DOCKER_ENV_PATH для Docker проекта."
    touch "$DOCKER_ENV_PATH"
  fi

  read -rp "📝 Хотите открыть $DOCKER_ENV_PATH в nano для редактирования? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Открываю $DOCKER_ENV_PATH в nano..."
    ${EDITOR:-nano} "$DOCKER_ENV_PATH"
  else
    echo "Продолжаем без редактирования Docker .env файла."
  fi
}

download_and_edit_run_env() {
  RUN_ENV_PATH="$CONFIG_DIR/${DOCKER_ENV_NAME}_run.env"
  echo "⬇️ Скачиваем run.env для скрипта в $RUN_ENV_PATH ..."
  curl -fsSL "$RUN_ENV_URL" -o "$RUN_ENV_PATH"
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка скачивания $RUN_ENV_PATH"
    exit 1
  fi
  echo "✅ Шаблон run.env скачан в $RUN_ENV_PATH"
  echo "📝 Открываю $RUN_ENV_PATH в nano через 1 секунду для обязательного заполнения..."
  sleep 1
  ${EDITOR:-nano} "$RUN_ENV_PATH"
}

replace_base_env_in_run() {
  local env_escaped=$(echo "$RUN_ENV_PATH" | sed 's/[\/&]/\\&/g')

  if grep -q "^export BASE_ENV=" "$RUN_SCRIPT_PATH"; then
    sed -i "s|^export BASE_ENV=.*|export BASE_ENV=\"$env_escaped\"|" "$RUN_SCRIPT_PATH"
    echo "✅ BASE_ENV в $RUN_SCRIPT_PATH заменён на \"$RUN_ENV_PATH\""
  else
    echo "export BASE_ENV=\"$RUN_ENV_PATH\"" >> "$RUN_SCRIPT_PATH"
    echo "✅ BASE_ENV добавлен в $RUN_SCRIPT_PATH"
  fi
}

make_run_executable() {
  chmod +x "$RUN_SCRIPT_PATH"
}

create_ssh_key() {
  read -rp "🔐 Хотите создать SSH ключ для доступа к репозиторию? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    read -rp "Введите имя файла ключа (без пути и расширения, например myproject): " key_name
    key_name="${key_name:-id_rsa}"
    key_path="$HOME/.ssh/$key_name"

    if [ -f "$key_path" ] || [ -f "${key_path}.pub" ]; then
      echo "⚠️ Файл ключа $key_path или $key_path.pub уже существует!"
      read -rp "Перезаписать? (y/n): " overwrite
      if ! [[ "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Отмена создания ключа."
        return
      fi
    fi

    ssh-keygen -t rsa -b 4096 -C "run_script_key" -f "$key_path"
    if [ $? -eq 0 ]; then
      echo "✅ SSH ключ создан: $key_path"
      echo "🔑 Публичный ключ:"
      cat "${key_path}.pub"
      echo "Добавьте этот ключ в настройки доступа вашего репозитория."

      # Обновляем run.sh или run.env — например, здесь run.sh
      local escaped_key_path=$(echo "$key_path" | sed 's/[\/&]/\\&/g')
      if grep -q "^export SSH_KEY_PATH=" "$RUN_SCRIPT_PATH"; then
        sed -i "s|^export SSH_KEY_PATH=.*|export SSH_KEY_PATH=\"$escaped_key_path\"|" "$RUN_SCRIPT_PATH"
      else
        echo "export SSH_KEY_PATH=\"$key_path\"" >> "$RUN_SCRIPT_PATH"
      fi

      echo "✅ Переменная SSH_KEY_PATH добавлена в $RUN_SCRIPT_PATH"
    else
      echo "❌ Ошибка при создании SSH ключа."
    fi
  else
    echo "Создание SSH ключа пропущено."
  fi
}

main() {
  download_run_script
  download_docker_env
  download_and_edit_run_env
  create_ssh_key
  replace_base_env_in_run
  make_run_executable

  echo -e "\n✅ Скрипт $RUN_SCRIPT_PATH готов к запуску."
  echo "📁 Ваш Docker .env файл: $DOCKER_ENV_PATH"
  echo "📁 Ваш run.env для скрипта: $RUN_ENV_PATH"
  echo "Для запуска используйте $RUN_SCRIPT_PATH"
}

main "$@"
